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

    private init() {
        // Check immediately when Mac wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.checkScheduled()
        }
    }

    /// Called when user manually clicks Auto-join — persists across restarts.
    func schedule(_ meeting: Meeting) {
        persistedScheduledIds.insert(meeting.id)
        UserDefaults.standard.set(Array(persistedScheduledIds), forKey: "persistedScheduledIds")
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
            guard meeting.endDate > Date() else { return }
            fire(meeting: meeting, url: url, joinDate: joinDate)
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
        if scheduled.isEmpty { stopPolling() }
    }

    /// Stops the timer AND remembers the user explicitly cancelled —
    /// prevents Minerva classes from re-scheduling on the next fetch.
    func cancelManually(_ id: String) {
        cancel(id)
        manuallyCancelled.insert(id)
        persistedScheduledIds.remove(id)
        UserDefaults.standard.set(Array(manuallyCancelled), forKey: "manuallyCancelledAutoJoin")
        UserDefaults.standard.set(Array(persistedScheduledIds), forKey: "persistedScheduledIds")
    }

    func isScheduled(_ id: String) -> Bool {
        scheduledIds.contains(id)
    }

    func isManuallyCancelled(_ id: String) -> Bool {
        manuallyCancelled.contains(id)
    }

    /// Called after each fetch — prunes stale entries for meetings that no longer exist.
    func cleanupCancelled(activeMeetingIds: Set<String>) {
        let prevCancelled = manuallyCancelled.count
        let prevPersisted = persistedScheduledIds.count
        manuallyCancelled = manuallyCancelled.filter { activeMeetingIds.contains($0) }
        persistedScheduledIds = persistedScheduledIds.filter { activeMeetingIds.contains($0) }
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

            // Meeting already ended — skip silently
            guard join.meeting.endDate > now else { continue }

            fire(meeting: join.meeting, url: join.url, joinDate: join.joinDate)
        }
        if scheduled.isEmpty { stopPolling() }
    }

    /// Scans for recently-started meetings the user hasn't joined and auto-joins them.
    /// Only fires within the first 10 minutes of a meeting's start — after that, the
    /// user has had a chance to join and chose not to, so we leave them alone.
    func checkInProgressMeetings() {
        guard !CallDetector.shared.isInCall else { return }
        let recentWindow: TimeInterval = 30 * 60
        for meeting in CalendarManager.shared.meetings {
            guard meeting.isInProgress,
                  Date().timeIntervalSince(meeting.startDate) <= recentWindow,
                  let url = meeting.joinURL,
                  !meeting.isPending,
                  !meeting.isDeclined,
                  !JoinTracker.shared.hasJoined(meeting),
                  !isManuallyCancelled(meeting.id) else { continue }
            FloatingAlertManager.shared.dismiss(meetingId: meeting.id)
            NSSound(named: "Funk")?.play()
            NSWorkspace.shared.open(url)
            JoinTracker.shared.markJoined(meeting)
            NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
        }
    }

    private func fire(meeting: Meeting, url: URL, joinDate: Date) {
        let lateBy = Date().timeIntervalSince(joinDate)

        if lateBy > 120 {
            // Woke up late — if the meeting is still going, join anyway.
            // If already in another call, skip silently; checkInProgressMeetings
            // will pick it up the moment that call ends.
            guard meeting.endDate > Date(), !CallDetector.shared.isInCall else { return }
        }

        FloatingAlertManager.shared.dismiss(meetingId: meeting.id)
        NSSound(named: "Funk")?.play()
        NSWorkspace.shared.open(url)
        JoinTracker.shared.markJoined(meeting)
        NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
    }
}
