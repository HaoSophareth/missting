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

    private struct ScheduledJoin {
        let meeting: Meeting
        let url: URL
        let joinDate: Date
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

    func schedule(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        cancel(meeting.id)

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

    func cancel(_ id: String) {
        scheduled.removeValue(forKey: id)
        scheduledIds.remove(id)
        if scheduled.isEmpty { stopPolling() }
    }

    func isScheduled(_ id: String) -> Bool {
        scheduledIds.contains(id)
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

    private func fire(meeting: Meeting, url: URL, joinDate: Date) {
        let lateBy = Date().timeIntervalSince(joinDate)

        // Fired more than 2 min late (Mac was asleep) — show alert, let user decide
        if lateBy > 120 {
            FloatingAlertManager.shared.present(meeting: meeting)
            return
        }

        NSSound(named: "Funk")?.play()
        NSWorkspace.shared.open(url)
        JoinTracker.shared.markJoined(meeting.id)
        NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
    }
}
