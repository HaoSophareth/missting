import AppKit
import Foundation

extension Notification.Name {
    static let meetingAutoJoined = Notification.Name("meetingAutoJoined")
}

/// Manages in-process timers for auto-joining meetings.
/// Lives at the app level so timers survive popover close.
final class AutoJoinManager: ObservableObject {
    static let shared = AutoJoinManager()

    @Published private(set) var scheduledIds: Set<String> = []
    private var timers: [String: Timer] = [:]

    private init() {}

    func schedule(_ meeting: Meeting) {
        guard let url = meeting.joinURL else { return }
        cancel(meeting.id) // replace any existing timer

        // Cancel pending notifications and dismiss only this meeting's floating alert
        NotificationManager.shared.cancelNotifications(for: meeting.id)
        FloatingAlertManager.shared.dismiss(meetingId: meeting.id)

        let offsetSeconds = Double(SettingsManager.shared.autoJoinOffset) * 60
        let joinDate = meeting.startDate.addingTimeInterval(-offsetSeconds)
        let msUntil = joinDate.timeIntervalSinceNow
        guard msUntil > 0 else {
            NSWorkspace.shared.open(url)
            return
        }

        let timer = Timer.scheduledTimer(withTimeInterval: msUntil, repeats: false) { [weak self] _ in
            self?.timers.removeValue(forKey: meeting.id)
            self?.scheduledIds.remove(meeting.id)

            // If the meeting is already over, skip silently
            guard meeting.endDate > Date() else { return }

            // If the timer fired more than 2 minutes late (e.g. Mac was asleep),
            // show a floating alert instead of auto-joining without the user knowing
            let expectedFireDate = meeting.startDate.addingTimeInterval(-offsetSeconds)
            let lateBy = Date().timeIntervalSince(expectedFireDate)
            if lateBy > 120 {
                FloatingAlertManager.shared.present(meeting: meeting)
                return
            }

            NSSound(named: "Funk")?.play()
            NSWorkspace.shared.open(url)
            JoinTracker.shared.markJoined(meeting.id)
            NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
        }
        timers[meeting.id] = timer
        scheduledIds.insert(meeting.id)
    }

    func cancel(_ id: String) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        scheduledIds.remove(id)
    }

    func isScheduled(_ id: String) -> Bool {
        scheduledIds.contains(id)
    }
}
