import AppKit
import Foundation

extension Notification.Name {
    static let meetingAutoJoined = Notification.Name("meetingAutoJoined")
}

/// Manages auto-join scheduling using a poll-based approach instead of long-duration timers,
/// so it remains accurate after Mac sleep/wake cycles.
final class AutoJoinManager: ObservableObject {
    static let shared = AutoJoinManager()

    @Published private(set) var scheduledIds: Set<String> = []

    /// Meeting IDs the user has explicitly cancelled auto-join for — persisted so
    /// Minerva classes don't re-schedule themselves after a refresh.
    private(set) var manuallyCancelled: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "manuallyCancelledAutoJoin") ?? [])
    }()

    /// Meeting IDs the user has manually scheduled — persisted so they survive restarts.
    private(set) var persistedScheduledIds: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "persistedScheduledIds") ?? [])
    }()

    private struct ScheduledJoin {
        let meeting: Meeting
        let url: URL
        let joinDate: Date
        var reminderShown: Bool = false
    }
    private var scheduled: [String: ScheduledJoin] = [:]
    private var pollTimer: Timer?
    /// Consecutive fetches each cancelled/persisted meeting id has been missing for.
    private var missingFetchCounts: [String: Int] = [:]
    /// Consecutive fetches each actively-scheduled meeting id has been missing for —
    /// separate from missingFetchCounts above, which only tracks the cancelled/
    /// persisted bookkeeping sets, not the live scheduled join itself.
    private var missingScheduledFetchCounts: [String: Int] = [:]

    /// Joins that came due while nobody was at the Mac (asleep, locked, display
    /// off, screen saver, other user). Held here instead of opened; handled when
    /// the user comes back. In-memory only: after a relaunch, the wake/launch
    /// in-progress scan rebuilds it.
    private var awayPending: [String: Meeting] = [:]

    /// Meetings currently showing the "Joining class in 10s" countdown.
    private var countingDown: Set<String> = []

    /// True while a join is held for the user's return or its countdown is
    /// showing. The calendar refresh must not re-schedule these: a class that
    /// hasn't started yet would otherwise be re-scheduled on the post-wake
    /// fetch and open immediately, skipping the countdown (and its Cancel).
    func isAwaitingReturn(_ id: String) -> Bool {
        awayPending[id] != nil || countingDown.contains(id)
    }

    /// When the user comes back within this many seconds of class start, join
    /// after a short countdown; later than that, only show the alert.
    static let returnAutoJoinWindow: TimeInterval = 15 * 60

    private init() {
        // Check immediately when Mac wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkScheduled()
        }
        NotificationCenter.default.addObserver(
            forName: .userReturned, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleUserReturned()
        }
    }

    /// Called when user manually clicks Auto-join — persists across restarts.
    func schedule(_ meeting: Meeting) {
        persistedScheduledIds.insert(meeting.id)
        UserDefaults.standard.set(Array(persistedScheduledIds), forKey: "persistedScheduledIds")
        // User re-engaged with this meeting — an earlier X no longer applies
        JoinTracker.shared.clearDismissed(meeting)
        scheduleInternal(meeting)
    }

    /// Called internally (auto-schedule on fetch) — does not persist.
    func scheduleInternal(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        cancel(meeting.id)
        // Clear any previous manual cancel when scheduling
        manuallyCancelled.remove(meeting.id)
        UserDefaults.standard.set(Array(manuallyCancelled), forKey: "manuallyCancelledAutoJoin")

        NotificationManager.shared.cancelNotifications(for: meeting.id)
        FloatingAlertManager.shared.dismiss(meetingId: meeting.id)

        let offsetSeconds = Double(SettingsManager.shared.autoJoinOffset) * 60
        let joinDate = meeting.startDate.addingTimeInterval(-offsetSeconds)

        // Already past the join time — fire immediately if meeting hasn't ended
        if joinDate <= Date() {
            fire(meeting: meeting, url: url)
            return
        }

        scheduled[meeting.id] = ScheduledJoin(meeting: meeting, url: url, joinDate: joinDate)
        scheduledIds.insert(meeting.id)
        ensurePolling()
    }

    /// Stops the timer without marking as manually cancelled (used internally).
    func cancel(_ id: String) {
        scheduled.removeValue(forKey: id)
        scheduledIds.remove(id)
        stopPollingIfIdle()
    }

    /// Stops the timer AND remembers the user explicitly cancelled —
    /// prevents Minerva classes from re-scheduling on the next fetch.
    func cancelManually(_ id: String) {
        cancel(id)
        awayPending.removeValue(forKey: id)
        countingDown.remove(id)
        manuallyCancelled.insert(id)
        persistedScheduledIds.remove(id)
        UserDefaults.standard.set(Array(manuallyCancelled), forKey: "manuallyCancelledAutoJoin")
        UserDefaults.standard.set(Array(persistedScheduledIds), forKey: "persistedScheduledIds")
    }

    func isScheduled(_ id: String) -> Bool {
        scheduledIds.contains(id)
    }

    /// Called when the user changes "Auto-join before start" in Settings. Every
    /// already-scheduled meeting's join time was computed once, at whatever offset
    /// was in effect when it was scheduled — nothing else ever revisits it, so
    /// without this a change to the setting only affects meetings scheduled after
    /// the change, not ones already sitting in `scheduled`. Reschedules each one
    /// through the normal path, which recomputes joinDate from the current offset,
    /// resets its reminder flag, and dismisses/refires the floating alert as needed.
    /// Snapshot first — scheduleInternal mutates `scheduled`, so iterating it
    /// directly while rescheduling would mutate the collection mid-iteration.
    func rescheduleAllForOffsetChange() {
        let meetings = scheduled.values.map(\.meeting)
        for meeting in meetings {
            scheduleInternal(meeting)
        }
    }

    func isManuallyCancelled(_ id: String) -> Bool {
        manuallyCancelled.contains(id)
    }

    /// Called after every fetch with the fresh meeting list — reconciles every
    /// already-scheduled meeting against it. A scheduled meeting's cached data
    /// (its own start time, most notably) is otherwise never revisited once set:
    /// editing/rescheduling an event in Google Calendar afterward left the old
    /// join time firing regardless, since CalendarManager's own list moves on
    /// but nothing told AutoJoinManager to look again. Same idea for a meeting
    /// that's deleted or fully cancelled outright — with nothing here, it would
    /// still auto-join at the original time forever.
    /// Debounced the same way cleanupCancelled is (a meeting must be missing
    /// from several consecutive fetches before being cancelled), so one
    /// transient/partial fetch can't cancel a real, still-upcoming join.
    func syncScheduled(with meetings: [Meeting]) {
        let freshById = Dictionary(uniqueKeysWithValues: meetings.map { ($0.id, $0) })

        var toReschedule: [Meeting] = []
        var toCancel: [String] = []
        for (id, join) in scheduled {
            if let fresh = freshById[id] {
                missingScheduledFetchCounts[id] = 0
                if fresh != join.meeting { toReschedule.append(fresh) }
            } else {
                let count = (missingScheduledFetchCounts[id] ?? 0) + 1
                missingScheduledFetchCounts[id] = count
                if count >= 5 { toCancel.append(id) }
            }
        }
        // Snapshot first, then mutate — scheduleInternal/cancel both mutate
        // `scheduled`, so acting mid-iteration over it isn't safe.
        for meeting in toReschedule { scheduleInternal(meeting) }
        for id in toCancel { cancel(id) }

        missingScheduledFetchCounts = missingScheduledFetchCounts.filter { scheduled[$0.key] != nil }
    }

    /// Called after each fetch — prunes stale entries for meetings that no longer exist.
    /// A meeting must be missing from several consecutive fetches before pruning, so a
    /// single failed calendar request can't wipe cancel state (which would let a
    /// cancelled Minerva class re-schedule itself).
    func cleanupCancelled(activeMeetingIds: Set<String>) {
        for id in manuallyCancelled.union(persistedScheduledIds) {
            missingFetchCounts[id] = activeMeetingIds.contains(id) ? 0 : (missingFetchCounts[id] ?? 0) + 1
        }
        let gone: (String) -> Bool = { (self.missingFetchCounts[$0] ?? 0) >= 5 }

        let prevCancelled = manuallyCancelled.count
        let prevPersisted = persistedScheduledIds.count
        manuallyCancelled = manuallyCancelled.filter { !gone($0) }
        persistedScheduledIds = persistedScheduledIds.filter { !gone($0) }

        // Drop counters for ids we no longer track so the dictionary can't grow stale
        let tracked = manuallyCancelled.union(persistedScheduledIds)
        missingFetchCounts = missingFetchCounts.filter { $0.value > 0 && tracked.contains($0.key) }
        if manuallyCancelled.count != prevCancelled {
            UserDefaults.standard.set(Array(manuallyCancelled), forKey: "manuallyCancelledAutoJoin")
        }
        if persistedScheduledIds.count != prevPersisted {
            UserDefaults.standard.set(Array(persistedScheduledIds), forKey: "persistedScheduledIds")
        }
    }

    // MARK: - Polling

    private func ensurePolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.checkScheduled()
        }
        pollTimer?.tolerance = 2
    }

    private func stopPollingIfIdle() {
        if scheduled.isEmpty && awayPending.isEmpty { stopPolling() }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func checkScheduled() {
        let now = Date()

        // Show the floating alert ~1 minute before join fires (once per meeting).
        // Only within 15–75s window so it never appears at the same moment auto-join fires.
        for meetingId in scheduled.keys {
            guard var join = scheduled[meetingId] else { continue }
            let secs = join.joinDate.timeIntervalSinceNow
            if !join.reminderShown && secs <= 75 && secs > 15 {
                join.reminderShown = true
                scheduled[meetingId] = join
                FloatingAlertManager.shared.present(meeting: join.meeting, autoJoinReminderMode: true)
            }
        }

        let due = scheduled.filter { $0.value.joinDate <= now }
        for (meetingId, join) in due {
            scheduled.removeValue(forKey: meetingId)
            scheduledIds.remove(meetingId)

            fire(meeting: join.meeting, url: join.url)
        }

        // Fallback for a missed return notification: if joins are waiting and
        // the user is present now, handle the return on this tick.
        if !awayPending.isEmpty && PresenceMonitor.shared.isPresent {
            handleUserReturned()
        }
        stopPollingIfIdle()
    }

    /// Scans for recently-started meetings the user scheduled for auto-join (Minerva
    /// classes or a manual Auto-join click) but hasn't joined yet — e.g. the Mac was
    /// asleep when the join time passed — and joins them. Only fires within the first
    /// 30 minutes of the start; never touches meetings that were never scheduled.
    /// Runs even while the user is on another call: it only opens the lobby.
    func checkInProgressMeetings() {
        let recentWindow: TimeInterval = 30 * 60
        for meeting in CalendarManager.shared.meetings {
            let isMinerva = meeting.joinURL?.host?.contains("class.minerva.edu") == true
            guard isMinerva || persistedScheduledIds.contains(meeting.id),
                  meeting.isInProgress,
                  Date().timeIntervalSince(meeting.startDate) <= recentWindow,
                  let url = meeting.joinURL,
                  !meeting.isPending,
                  !meeting.isDeclined,
                  !JoinTracker.shared.hasJoined(meeting),
                  !JoinTracker.shared.isDismissed(meeting),
                  !isManuallyCancelled(meeting.id) else { continue }
            fire(meeting: meeting, url: url)
        }
    }

    private func fire(meeting: Meeting, url: URL) {
        // Never join a meeting that already ended (possible after a long sleep).
        guard meeting.endDate > Date() else { return }

        // Only open the link if someone is at the Mac. Opening a Forum link puts
        // the student in class (thumbnail visible) with no further click, so
        // joining a locked/asleep/dark Mac makes them look present when they
        // aren't. Hold it until they come back instead.
        // Being on another call is NOT a blocker (for Zoom/Meet that only opens
        // the lobby).
        if let reason = PresenceMonitor.shared.awayReason {
            PresenceMonitor.shared.log("holding join for \"\(meeting.title)\": \(reason)")
            awayPending[meeting.id] = meeting
            ensurePolling()
            return
        }

        openNow(meeting: meeting, url: url)
    }

    private func openNow(meeting: Meeting, url: URL) {
        PresenceMonitor.shared.log("opening \"\(meeting.title)\"")
        FloatingAlertManager.shared.dismiss(meetingId: meeting.id)
        NSSound(named: "Funk")?.play()
        NSWorkspace.shared.open(url)
        JoinTracker.shared.markJoined(meeting)
        NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
    }

    // MARK: - Coming back

    /// The user is back at the Mac. Within the first 15 min of class: 10s
    /// countdown, then join (cancellable). Later: plain alert, click to join.
    private func handleUserReturned() {
        guard !awayPending.isEmpty else { return }
        let pending = awayPending.values
        awayPending.removeAll()
        stopPollingIfIdle()

        for meeting in pending {
            guard meeting.endDate > Date(),
                  meeting.joinURL != nil,
                  !JoinTracker.shared.hasJoined(meeting),
                  !isManuallyCancelled(meeting.id) else { continue }
            let elapsed = Date().timeIntervalSince(meeting.startDate)
            if elapsed <= Self.returnAutoJoinWindow {
                PresenceMonitor.shared.log("back \(Int(elapsed / 60)) min into \"\(meeting.title)\": countdown")
                countingDown.insert(meeting.id)
                FloatingAlertManager.shared.presentCountdown(meeting: meeting)
            } else {
                PresenceMonitor.shared.log("back \(Int(elapsed / 60)) min into \"\(meeting.title)\": alert only")
                FloatingAlertManager.shared.present(meeting: meeting)
            }
        }
    }

    /// Countdown on the return alert finished — join, unless the user is gone again.
    func countdownFinished(_ meeting: Meeting) {
        countingDown.remove(meeting.id)
        guard let url = meeting.joinURL,
              !JoinTracker.shared.hasJoined(meeting),
              !isManuallyCancelled(meeting.id) else { return }
        fire(meeting: meeting, url: url)
    }

    /// The countdown alert closed some other way (Join now clicked).
    func countdownEnded(_ id: String) {
        countingDown.remove(id)
    }
}
