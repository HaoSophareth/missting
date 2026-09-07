import Foundation

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let joinURL: URL?
    let calendarEmail: String?
    let calendarId: String?
    /// RFC5545 UID — identical across every calendar/account copy of the same real
    /// event (organizer's, each attendee's, any calendar it's duplicated onto), unlike
    /// `id` which Google mints per-calendar. Used to detect and merge duplicate copies.
    let iCalUID: String?
    /// "accepted", "tentative", "needsAction", "declined"
    let responseStatus: String

    /// Identity for cross-calendar dedup: same real event + same occurrence. Paired
    /// with startDate because a recurring series shares one iCalUID across all its
    /// instances — without the date, different days of the same series would collide.
    var dedupKey: String { "\(iCalUID ?? id)|\(Int(startDate.timeIntervalSince1970))" }

    var isPending: Bool     { responseStatus == "needsAction" }
    var isDeclined: Bool    { responseStatus == "declined" }

    var minsUntilStart: Int { Int((startDate.timeIntervalSinceNow / 60).rounded()) }
    var isInProgress: Bool  { startDate <= Date() && endDate > Date() }
    var isMissed: Bool      { joinURL != nil && endDate < Date() && !JoinTracker.shared.hasJoined(self) }
    var minsElapsed: Int    { Int((Date().timeIntervalSince(startDate) / 60).rounded()) }
    var minsRemaining: Int  { Int((endDate.timeIntervalSinceNow / 60).rounded()) }
}

/// Formats a minute count as human-readable duration: "45m" under an hour,
/// "3h" or "3h 12m" at or above an hour.
func formatDuration(minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes)m" }
    let hours = minutes / 60
    let mins = minutes % 60
    return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m"
}

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let colorHex: String?
}

/// Diagnoses exactly why the Minerva class calendar is or isn't working, rather
/// than a single connected/disconnected bool. The old bool went green as soon as
/// ANY calendar's name merely contained "minerva" — true even when that calendar
/// was toggled off in Missting's own Calendars list, unreadable (a permission
/// error silently produced zero events), or just wasn't the personal
/// forum.minerva.edu feed at all. Each non-fully-working case names the calendar
/// involved so Settings can point at the actual fix instead of a flat "connected".
enum MinervaStatus: Equatable {
    /// No calendar with "minerva" in its name exists at all — show setup steps.
    case notConnected
    /// A minerva-named calendar exists, but every copy of it is turned off in
    /// the Calendars list above, so its events are never fetched.
    case disabledInSettings(calendarName: String)
    /// Enabled, but the last fetch for it returned a non-200 (permission/sharing
    /// issue) — Google silently gets skipped rather than surfaced, so this is
    /// the only way to know it happened.
    case fetchFailed(calendarName: String)
    /// Enabled and readable, but no forum.minerva.edu class link turned up in
    /// the fetch window. Often just means no class is scheduled soon; can also
    /// mean Google hasn't re-synced this externally-subscribed calendar yet.
    case noClassesInWindow(calendarName: String)
    /// Enabled, readable, and a real class.minerva.edu join link was decoded
    /// from it — the only case that guarantees auto-join has something to do.
    case connected
}

/// One calendar's event fetch outcome — `failed` distinguishes "Google rejected
/// this request" from "this calendar genuinely has no events right now", which a
/// bare `[Meeting]` can't.
private struct CalendarFetchResult {
    let meetings: [Meeting]
    let failed: Bool
}

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var meetings: [Meeting] = []
    @Published var availableCalendars: [CalendarInfo] = []
    @Published var minervaStatus: MinervaStatus = .notConnected

    private var refreshTimer: Timer?
    private let auth = GoogleAuthManager.shared

    private static let iso = ISO8601DateFormatter()
    // Known video-conferencing platforms — matched regardless of which field
    // (location or description) the link happens to sit in.
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https://(?:meet\.google\.com/[^\s\"<]+|[\w.\-]*zoom\.us/(?:j|my)/[^\s\"<]+|teams\.microsoft\.com/[^\s\"<]+|teams\.live\.com/[^\s\"<]+|[\w.\-]*webex\.com/[^\s\"<]+|[\w.\-]*gotomeet(?:ing)?\.(?:com|me)/[^\s\"<]+|bluejeans\.com/[^\s\"<]+|whereby\.com/[^\s\"<]+|meet\.jit\.si/[^\s\"<]+|join\.me/[^\s\"<]+|chime\.aws/[^\s\"<]+|8x8\.vc/[^\s\"<]+|ringcentral\.com/[^\s\"<]*meet[^\s\"<]*|calendly\.com/events/[\w-]+/(?:google_meet|zoom|microsoft_teams)[^\s\"<]*)"#
    )
    private static let anyURLPattern = try! NSRegularExpression(
        pattern: #"https://[^\s\"<]+"#
    )
    // Matches Minerva Academic calendar event URLs, captures the class ID at the end
    // e.g. https://forum.minerva.edu/app/courses/3797/sections/13018/classes/101243
    private static let minervaForumPattern = try! NSRegularExpression(
        pattern: #"https://forum\.minerva\.edu/\S*/classes/(\d+)"#
    )

    var isAccessGranted: Bool { auth.isSignedIn }

    /// Accepted (+ tentative) meetings on the given day. Includes link-less events when showAllEvents is on.
    func acceptedMeetings(daysFromToday: Int) -> [Meeting] {
        let cal      = Calendar.current
        let target   = cal.date(byAdding: .day, value: daysFromToday, to: cal.startOfDay(for: Date()))!
        let showAll  = SettingsManager.shared.showAllEvents
        let now      = Date()
        return meetings.filter {
            cal.isDate($0.startDate, inSameDayAs: target)
            && (showAll || $0.joinURL != nil)
            && !$0.isPending
            && !$0.isDeclined
            // Hide meetings that ended and were already joined — they're done.
            // Ended meetings that weren't joined stay visible as "Missed".
            && !($0.endDate < now && JoinTracker.shared.hasJoined($0))
        }
    }

    /// Pending (needsAction) meetings on the given day.
    func pendingMeetings(daysFromToday: Int) -> [Meeting] {
        let cal    = Calendar.current
        let target = cal.date(byAdding: .day, value: daysFromToday, to: cal.startOfDay(for: Date()))!
        return meetings.filter {
            cal.isDate($0.startDate, inSameDayAs: target) && $0.isPending
        }
    }

    private init() {}

    func startRefreshingIfSignedIn() {
        guard auth.isSignedIn else { return }
        fetchMeetings()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.fetchMeetings()
        }
    }

    func fetchMeetings() {
        Task { @MainActor in
            do {
                let token = try await auth.getValidToken()
                let result = try await fetchFromAllCalendars(token: token)
                self.meetings = result.meetings
                self.minervaStatus = result.minervaStatus
                NotificationManager.shared.checkAndNotify(
                    meetings: self.meetings,
                    offsets: SettingsManager.shared.enabledOffsets
                )
                autoScheduleMinervaClasses(result.meetings)
            } catch {
                print("Calendar fetch error:", error)
                // A rejected refresh token means GoogleAuthManager already signed this
                // account out — stop polling and clear stale data so the UI falls back
                // to the sign-in prompt instead of quietly showing yesterday's meetings.
                if !auth.isSignedIn {
                    refreshTimer?.invalidate()
                    self.meetings = []
                }
            }
        }
    }

    // MARK: - Fetch all calendars then their events

    private func fetchFromAllCalendars(token: String) async throws -> (meetings: [Meeting], minervaStatus: MinervaStatus) {
        let calendars = try await fetchCalendarList(token: token)
        let now = Date()
        let disabled = SettingsManager.shared.disabledCalendarIds

        // Publish available calendars on main actor
        await MainActor.run { self.availableCalendars = calendars }

        let enabledIds = Set(calendars.map(\.id).filter { !disabled.contains($0) })

        // Fetch events from all calendars concurrently
        var allMeetings: [Meeting] = []
        // Calendars whose event fetch came back non-200 — fetchEvents swallows the
        // error and returns no events rather than failing the whole refresh, so this
        // is the only record that it happened instead of the calendar just being
        // legitimately empty.
        var failedCalendarIds: Set<String> = []

        // Collect all copies (same event can appear in multiple calendars)
        var allCopies: [String: [Meeting]] = [:]
        try await withThrowingTaskGroup(of: (String, CalendarFetchResult).self) { group in
            for calId in enabledIds {
                group.addTask {
                    (calId, try await self.fetchEvents(token: token, calendarId: calId, now: now))
                }
            }
            for try await (calId, result) in group {
                if result.failed { failedCalendarIds.insert(calId) }
                for meeting in result.meetings {
                    allCopies[meeting.dedupKey, default: []].append(meeting)
                }
            }
        }

        // Merge: prefer the copy where self is explicitly an attendee.
        // If ANY copy is pending/declined, respect that over a defaulted "accepted".
        for (_, copies) in allCopies {
            allMeetings.append(Self.pickRepresentative(copies))
        }

        // Second pass: some calendars (e.g. a booking-page alias calendar) create a
        // genuinely separate event resource for the same real meeting instead of
        // propagating one invite, so it carries its own iCalUID and slips past the
        // pass above. Collapse those too when title + start + end all match exactly —
        // that combination essentially never happens for two truly unrelated meetings.
        var byContent: [String: [Meeting]] = [:]
        for meeting in allMeetings {
            let key = "\(meeting.title)|\(Int(meeting.startDate.timeIntervalSince1970))|\(Int(meeting.endDate.timeIntervalSince1970))"
            byContent[key, default: []].append(meeting)
        }
        allMeetings = byContent.values.map(Self.pickRepresentative)

        // Diagnose Minerva end to end instead of a flat present/absent check.
        // A real class link, found anywhere among the enabled calendars, is the
        // one unambiguous "this works" signal — check that first and skip the
        // name-guessing entirely when it's already true.
        let hasClassLink = allMeetings.contains { $0.joinURL?.host?.contains("class.minerva.edu") == true }
        let minervaStatus: MinervaStatus
        if hasClassLink {
            minervaStatus = .connected
        } else {
            // Only reached when nothing has actually worked yet, so naming a
            // specific calendar needs real evidence, not a guess. "minerva" alone
            // matches all sorts of things that are never the personal Forum feed —
            // community calendars ("Humans of Minerva"), campus/regional ones
            // ("Buenos Aires Calendar | Minerva University"), even the signed-in
            // account's own primary calendar (its id is just their @minerva.edu
            // email). "Minerva" is the university's own name, so it shows up
            // everywhere — matching on it alone means constantly finding some
            // unrelated calendar to blame. Only the two actual naming patterns
            // Forum's own "Copy Calendar Link" export has been seen producing —
            // "[Minerva] <name>" or something containing "academic" — count as a
            // real candidate; anything else falls straight through to notConnected
            // below rather than pointing at a calendar that likely has nothing to
            // do with classes.
            let selfEmail = auth.userEmail?.lowercased()
            let minervaCalendars = calendars.filter {
                let name = $0.name.lowercased()
                return (name.hasPrefix("[minerva]") || name.contains("academic")) && $0.id.lowercased() != selfEmail
            }
            if let disabled = minervaCalendars.first(where: { !enabledIds.contains($0.id) }) {
                minervaStatus = .disabledInSettings(calendarName: disabled.name)
            } else if let failed = minervaCalendars.first(where: { failedCalendarIds.contains($0.id) }) {
                minervaStatus = .fetchFailed(calendarName: failed.name)
            } else if let candidate = minervaCalendars.first {
                minervaStatus = .noClassesInWindow(calendarName: candidate.name)
            } else {
                minervaStatus = .notConnected
            }
        }

        let filtered = allMeetings
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        return (filtered, minervaStatus)
    }

    /// Picks which copy of a duplicated event represents it: prefer the copy where
    /// self is explicitly an attendee, so a pending/declined status on any copy
    /// isn't shadowed by a defaulted "accepted" from a calendar with no attendee data.
    ///
    /// Copies arrive in task-group completion order, which varies run to run even
    /// when the exact same calendars produce the exact same copies — so we sort by
    /// a stable key first. Without this, the chosen copy's `id` (what JoinTracker,
    /// AutoJoinManager, and the dismissed-cards set all key off) could flip between
    /// refreshes for any event duplicated across two enabled calendars.
    private static func pickRepresentative(_ copies: [Meeting]) -> Meeting {
        let sorted = copies.sorted { ($0.calendarId ?? "", $0.id) < ($1.calendarId ?? "", $1.id) }
        return sorted.first { $0.calendarEmail != nil && $0.responseStatus != "accepted" }
            ?? sorted.first { $0.calendarEmail != nil }
            ?? sorted[0]
    }

    private func fetchCalendarList(token: String) async throws -> [CalendarInfo] {
        var allItems: [CalendarItem] = []
        var pageToken: String? = nil

        repeat {
            var urlStr = "https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader&showHidden=true&maxResults=250"
            if let pt = pageToken { urlStr += "&pageToken=\(pt)" }
            var req = URLRequest(url: URL(string: urlStr)!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw CalError.http(http.statusCode)
            }

            let body = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            allItems.append(contentsOf: body.items ?? [])
            pageToken = body.nextPageToken
        } while pageToken != nil

        // Every calendar the account can read, regardless of Google Calendar's own
        // "selected" (shown in my view) flag. That flag is purely a display
        // preference for Google's own UI — a calendar added via "From URL" can land
        // with selected=false and never show here otherwise, which is exactly how a
        // freshly-subscribed Minerva class calendar can go undetected with zero
        // indication why. Missting has its own enable/disable toggle in Settings
        // (disabledCalendarIds) for the user to actually control what's fetched, so
        // filtering on Google's flag here only hides calendars without ever asking.
        return allItems
            .map { CalendarInfo(id: $0.id, name: $0.summary ?? $0.id, colorHex: $0.backgroundColor) }
    }

    private func fetchEvents(token: String, calendarId: String, now: Date) async throws -> CalendarFetchResult {
        let cal = Calendar.current
        let windowStart = cal.startOfDay(for: now)
        let windowEnd = cal.date(byAdding: .day, value: 8, to: windowStart)!

        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
        comps.queryItems = [
            .init(name: "timeMin",      value: Self.iso.string(from: windowStart)),
            .init(name: "timeMax",      value: Self.iso.string(from: windowEnd)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy",      value: "startTime"),
            .init(name: "maxResults",   value: "50"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // Skip calendars we can't read rather than failing the whole refresh —
            // but remember it happened, so a calendar that's silently unreadable
            // (permission/sharing issue) isn't indistinguishable from one that's
            // genuinely just empty.
            return CalendarFetchResult(meetings: [], failed: true)
        }

        let body    = try JSONDecoder().decode(EventsResponse.self, from: data)
        let calEmail = calendarId.contains("@") ? calendarId : nil
        // Filter out all-day events (no dateTime) and events that ended before today started
        let meetings = (body.items ?? [])
            .filter { $0.start?.dateTime != nil }
            .compactMap { toMeeting($0, calendarEmail: calEmail, calendarId: calendarId) }
        return CalendarFetchResult(meetings: meetings, failed: false)
    }

    // MARK: - Mapping

    private func toMeeting(_ e: GCalEvent, calendarEmail: String?, calendarId: String) -> Meeting? {
        guard let startStr = e.start?.dateTime,
              let start    = Self.iso.date(from: startStr) else { return nil }
        let end = e.end?.dateTime.flatMap { Self.iso.date(from: $0) }
               ?? start.addingTimeInterval(3600)

        // Use the stored user email to find self in attendees list
        let knownEmail = GoogleAuthManager.shared.userEmail ?? calendarEmail
        let selfAttendee = e.attendees?.first(where: { $0.isSelf == true })
                        ?? e.attendees?.first(where: { att in
                               guard let e = att.email, let k = knownEmail else { return false }
                               return e.lowercased() == k.lowercased()
                           })
        let selfEmail      = selfAttendee?.email ?? knownEmail
        // Only mark pending if the user is explicitly an attendee with needsAction.
        // If the user isn't in the attendees list it's a shared/community calendar event → treat as accepted.
        let responseStatus = selfAttendee?.responseStatus ?? "accepted"

        let title = e.summary ?? "Untitled"
        let joinURL = extractLink(e, accountEmail: selfEmail)

        return Meeting(id:             e.id ?? UUID().uuidString,
                       title:          title,
                       startDate:      start,
                       endDate:        end,
                       joinURL:        joinURL,
                       calendarEmail:  selfEmail,
                       calendarId:     calendarId,
                       iCalUID:        e.iCalUID,
                       responseStatus: responseStatus)
    }

    private func extractLink(_ e: GCalEvent, accountEmail: String?) -> URL? {
        let fullText = [e.location, e.description].compactMap { $0 }.joined(separator: " ")

        // Minerva Academic calendar
        if let minervaURL = Self.extractMinervaClassURL(from: fullText) {
            return minervaURL
        }

        let rawURL: URL? = {
            // 1. Explicit Google Meet link attached to the event
            if let s = e.hangoutLink { return URL(string: s) }

            // 2. Structured conference data (Zoom/Teams/etc. added via a Calendar
            // conferencing add-on). Many of these events carry no plain-text link
            // in location/description at all — the join URL only exists here.
            if let entryPoints = e.conferenceData?.entryPoints {
                let entryPoint = entryPoints.first { $0.entryPointType == "video" }
                              ?? entryPoints.first { $0.entryPointType == "more" }
                if let uri = entryPoint?.uri, let url = URL(string: uri) {
                    return url
                }
            }

            // 3. Known video-call platform links, wherever they sit — location or
            // description. Google Calendar descriptions can contain raw HTML (e.g.
            // Zoom's <a href="...">), so the extracted substring may still have
            // entity-encoded characters like &amp;.
            let range = NSRange(fullText.startIndex..., in: fullText)
            if let match = Self.linkPattern.firstMatch(in: fullText, range: range),
               let sr = Range(match.range, in: fullText) {
                return URL(string: Self.decodeHTMLEntities(String(fullText[sr])))
            }

            // 4. Fallback for custom/unbranded booking platforms (e.g. Preply) that put
            // their own call link in the location field under no recognized domain.
            // Scoped to location only (not description, which is too noisy with
            // unrelated links) and filtered against known non-meeting link types
            // (maps, docs, drive, calendar, etc.) so those aren't mistaken for it.
            if let location = e.location, !location.isEmpty {
                let locRange = NSRange(location.startIndex..., in: location)
                let matches = Self.anyURLPattern.matches(in: location, range: locRange)
                for match in matches {
                    guard let sr = Range(match.range, in: location),
                          let url = URL(string: Self.decodeHTMLEntities(String(location[sr]))),
                          !Self.isKnownNonMeetingLink(url) else { continue }
                    return url
                }
            }
            return nil
        }()

        guard let url = rawURL else { return nil }

        if let email = accountEmail, url.host?.contains("meet.google.com") == true {
            var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var items = comps?.queryItems ?? []
            items.removeAll { $0.name == "authuser" }
            items.append(URLQueryItem(name: "authuser", value: email))
            comps?.queryItems = items
            return comps?.url ?? url
        }
        return url
    }

    /// Link types that are never a meeting to join — a physical address, a shared
    /// file, a calendar entry, a social/media page, etc. — so the location-field
    /// fallback (rule 4) doesn't mistake one for the join link.
    private static func isKnownNonMeetingLink(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()

        if host == "maps.app.goo.gl" || host.hasSuffix(".maps.app.goo.gl") { return true }

        if host.hasSuffix("google.com") {
            let googleNonMeetingPrefixes = [
                "/maps", "/document", "/spreadsheets", "/presentation", "/forms",
                "/drive", "/file", "/calendar", "/photos", "/contacts",
            ]
            return googleNonMeetingPrefixes.contains { path.hasPrefix($0) }
        }

        let nonMeetingHosts: Set<String> = [
            "docs.google.com", "drive.google.com", "photos.google.com", "photos.app.goo.gl",
            "calendar.google.com", "youtube.com", "youtu.be", "github.com", "notion.so",
            "www.notion.so", "dropbox.com", "www.dropbox.com", "twitter.com", "x.com",
            "facebook.com", "www.facebook.com", "instagram.com", "linkedin.com",
            "www.linkedin.com", "amazon.com", "www.amazon.com",
        ]
        return nonMeetingHosts.contains(host)
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")
        ]
        return entities.reduce(s) { result, pair in
            result.replacingOccurrences(of: pair.0, with: pair.1)
        }
    }

    private static func extractMinervaClassURL(from text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = minervaForumPattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: text) else { return nil }
        let classId = String(text[idRange])
        return URL(string: "https://class.minerva.edu/classes/\(classId)")
    }

    private func autoScheduleMinervaClasses(_ meetings: [Meeting]) {
        let autoJoin = AutoJoinManager.shared
        let activeIds = Set(meetings.map(\.id))
        autoJoin.cleanupCancelled(activeMeetingIds: activeIds)

        for meeting in meetings {
            let isMinerva = meeting.joinURL?.host?.contains("class.minerva.edu") == true
            let isPersisted = autoJoin.persistedScheduledIds.contains(meeting.id)
            guard (isMinerva || isPersisted),
                  meeting.endDate > Date(),
                  !meeting.isInProgress,
                  !meeting.isPending,
                  !meeting.isDeclined,
                  !JoinTracker.shared.hasJoined(meeting),
                  !autoJoin.isScheduled(meeting.id),
                  !autoJoin.isManuallyCancelled(meeting.id) else { continue }
            autoJoin.scheduleInternal(meeting)
        }
    }

    enum CalError: Error { case http(Int) }
}

// MARK: - Codable models

private struct CalendarListResponse: Codable {
    let items: [CalendarItem]?
    let nextPageToken: String?
}
private struct CalendarItem: Codable {
    let id: String
    let summary: String?
    let backgroundColor: String?
    let selected: Bool?
}
private struct EventsResponse: Codable { let items: [GCalEvent]? }
private struct GCalEvent: Codable {
    let id: String?
    let iCalUID: String?
    let summary: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let hangoutLink: String?
    let location: String?
    let description: String?
    let conferenceData: ConferenceData?
    let attendees: [Attendee]?
}
private struct ConferenceData: Codable {
    let entryPoints: [ConferenceEntryPoint]?
}
private struct ConferenceEntryPoint: Codable {
    let entryPointType: String?  // "video", "phone", "sip", "more"
    let uri: String?
}
private struct Attendee: Codable {
    let email: String?
    let isSelf: Bool?
    let responseStatus: String?
    enum CodingKeys: String, CodingKey {
        case email; case isSelf = "self"; case responseStatus
    }
}
private struct EventDateTime: Codable {
    let dateTime: String?
    let date: String?
}
