import Foundation

struct Meeting: Identifiable, Equatable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let joinURL: URL?
    let calendarEmail: String?
    let calendarId: String?
    /// "accepted", "tentative", "needsAction", "declined"
    let responseStatus: String

    var isPending: Bool     { responseStatus == "needsAction" }
    var isDeclined: Bool    { responseStatus == "declined" }

    var minsUntilStart: Int { Int((startDate.timeIntervalSinceNow / 60).rounded()) }
    var isInProgress: Bool  { startDate <= Date() && endDate > Date() }
    var isMissed: Bool      { endDate < Date() && !JoinTracker.shared.hasJoined(id) }
    var minsElapsed: Int    { Int((Date().timeIntervalSince(startDate) / 60).rounded()) }
    var minsRemaining: Int  { Int((endDate.timeIntervalSinceNow / 60).rounded()) }
}

struct CalendarInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let colorHex: String?
}

final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var meetings: [Meeting] = []
    @Published var availableCalendars: [CalendarInfo] = []
    /// True after a fetch finds at least one event with a forum.minerva.edu link,
    /// meaning the Academic calendar is connected and working.
    @Published var minervaCalendarConnected: Bool = false

    private var refreshTimer: Timer?
    private let auth = GoogleAuthManager.shared

    private static let iso = ISO8601DateFormatter()
    private static let linkPattern = try! NSRegularExpression(
        pattern: #"https://(meet\.google\.com|[\w.\-]*zoom\.us/j|teams\.microsoft\.com)/\S+"#
    )
    // Matches Minerva Academic calendar event URLs, captures the class ID at the end
    // e.g. https://forum.minerva.edu/app/courses/3797/sections/13018/classes/101243
    private static let minervaForumPattern = try! NSRegularExpression(
        pattern: #"https://forum\.minerva\.edu/\S*/classes/(\d+)"#
    )

    var isAccessGranted: Bool { auth.isSignedIn }

    /// Accepted (+ tentative) meetings on the given day that have a join link.
    func acceptedMeetings(daysFromToday: Int) -> [Meeting] {
        let cal    = Calendar.current
        let target = cal.date(byAdding: .day, value: daysFromToday, to: cal.startOfDay(for: Date()))!
        return meetings.filter {
            cal.isDate($0.startDate, inSameDayAs: target)
            && $0.joinURL != nil
            && !$0.isPending
            && !$0.isDeclined
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

    /// RSVP to a meeting — updates local state instantly, syncs to Google Calendar in background.
    func rsvp(meeting: Meeting, accept: Bool) {
        // Optimistic update: change responseStatus locally right now
        let newStatus = accept ? "accepted" : "declined"
        if let idx = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[idx] = Meeting(
                id:             meeting.id,
                title:          meeting.title,
                startDate:      meeting.startDate,
                endDate:        meeting.endDate,
                joinURL:        meeting.joinURL,
                calendarEmail:  meeting.calendarEmail,
                calendarId:     meeting.calendarId,
                responseStatus: newStatus
            )
        }

        // Sync to Google Calendar in the background
        Task {
            do {
                let token = try await auth.getValidToken()
                guard let selfEmail = meeting.calendarEmail ?? auth.userEmail else { return }
                let encodedEvent = meeting.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? meeting.id

                // Fetch full event to preserve all attendees
                var getReq = URLRequest(url: URL(string:
                    "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedEvent)")!)
                getReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (getData, _) = try await URLSession.shared.data(for: getReq)
                guard let eventJson = try? JSONSerialization.jsonObject(with: getData) as? [String: Any],
                      var attendees = eventJson["attendees"] as? [[String: Any]] else { return }

                for i in attendees.indices {
                    if let email = attendees[i]["email"] as? String, email == selfEmail {
                        attendees[i]["responseStatus"] = newStatus
                    }
                }

                var patchReq = URLRequest(url: URL(string:
                    "https://www.googleapis.com/calendar/v3/calendars/primary/events/\(encodedEvent)?sendUpdates=all")!)
                patchReq.httpMethod = "PATCH"
                patchReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                patchReq.httpBody = try? JSONSerialization.data(withJSONObject: ["attendees": attendees])
                _ = try? await URLSession.shared.data(for: patchReq)
            } catch {
                print("RSVP error:", error)
            }
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
                self.minervaCalendarConnected = result.hasMinerva
                MenuBarManager.shared.updateStatusText(result.meetings)
                NotificationManager.shared.checkAndNotify(
                    meetings: self.meetings,
                    offsets: SettingsManager.shared.enabledOffsets
                )
            } catch {
                print("Calendar fetch error:", error)
            }
        }
    }

    // MARK: - Fetch all calendars then their events

    private func fetchFromAllCalendars(token: String) async throws -> (meetings: [Meeting], hasMinerva: Bool) {
        let calendars = try await fetchCalendarList(token: token)
        let now = Date()
        let disabled = SettingsManager.shared.disabledCalendarIds

        // Publish available calendars on main actor
        await MainActor.run { self.availableCalendars = calendars }

        let enabledIds = calendars.map(\.id).filter { !disabled.contains($0) }

        // Fetch events from all calendars concurrently
        var allMeetings: [Meeting] = []

        // Collect all copies (same event can appear in multiple calendars)
        var allCopies: [String: [Meeting]] = [:]
        try await withThrowingTaskGroup(of: [Meeting].self) { group in
            for calId in enabledIds {
                group.addTask {
                    try await self.fetchEvents(token: token, calendarId: calId, now: now)
                }
            }
            for try await meetings in group {
                for meeting in meetings {
                    allCopies[meeting.id, default: []].append(meeting)
                }
            }
        }

        // Merge: prefer the copy where self is explicitly an attendee.
        // If ANY copy is pending/declined, respect that over a defaulted "accepted".
        for (_, copies) in allCopies {
            let selfCopy = copies.first { $0.calendarEmail != nil && $0.responseStatus != "accepted" }
                        ?? copies.first { $0.calendarEmail != nil }
                        ?? copies[0]
            allMeetings.append(selfCopy)
        }

        // Check for Minerva before time-filtering — catches today's already-joined classes too
        let hasMinerva = allMeetings.contains { $0.joinURL?.host?.contains("class.minerva.edu") == true }

        let filtered = allMeetings
            .filter { $0.joinURL != nil && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        return (filtered, hasMinerva)
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

        // Only expose calendars the user has checked in Google Calendar
        return allItems
            .filter { $0.selected == true }
            .map { CalendarInfo(id: $0.id, name: $0.summary ?? $0.id, colorHex: $0.backgroundColor) }
    }

    private func fetchEvents(token: String, calendarId: String, now: Date) async throws -> [Meeting] {
        let cal = Calendar.current
        // Start: beginning of today (catches today's missed meetings)
        let windowStart = cal.startOfDay(for: now)
        // End: end of tomorrow (full two-day window)
        let dayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: cal.startOfDay(for: now))!
        let windowEnd = dayAfterTomorrow

        let encodedId = calendarId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendarId
        var comps = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events")!
        comps.queryItems = [
            .init(name: "timeMin",      value: Self.iso.string(from: windowStart)),
            .init(name: "timeMax",      value: Self.iso.string(from: windowEnd)),
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy",      value: "startTime"),
            .init(name: "maxResults",   value: "20"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return [] // skip calendars we can't read rather than failing everything
        }

        let body    = try JSONDecoder().decode(EventsResponse.self, from: data)
        let calEmail = calendarId.contains("@") ? calendarId : nil
        // Filter out all-day events (no dateTime) and events that ended before today started
        return (body.items ?? [])
            .filter { $0.start?.dateTime != nil }
            .compactMap { toMeeting($0, calendarEmail: calEmail, calendarId: calendarId) }
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
                       responseStatus: responseStatus)
    }

    private func extractLink(_ e: GCalEvent, accountEmail: String?) -> URL? {
        let text = [e.location, e.description].compactMap { $0 }.joined(separator: " ")

        // Minerva Academic calendar: extract class ID from forum URL and build class meeting link
        // forum.minerva.edu/.../classes/101243  →  class.minerva.edu/classes/101243
        if let minervaURL = Self.extractMinervaClassURL(from: text) {
            return minervaURL
        }

        let rawURL: URL? = {
            if let s = e.hangoutLink { return URL(string: s) }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = Self.linkPattern.firstMatch(in: text, range: range),
                  let sr    = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[sr]))
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

    private static func extractMinervaClassURL(from text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = minervaForumPattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let idRange = Range(match.range(at: 1), in: text) else { return nil }
        let classId = String(text[idRange])
        return URL(string: "https://class.minerva.edu/classes/\(classId)")
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
    let summary: String?
    let start: EventDateTime?
    let end: EventDateTime?
    let hangoutLink: String?
    let location: String?
    let description: String?
    let attendees: [Attendee]?
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
