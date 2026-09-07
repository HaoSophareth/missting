import Foundation

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    /// Minutes before a meeting to send a notification.
    @Published var notificationOffset: Int {
        didSet {
            UserDefaults.standard.set(notificationOffset, forKey: "notificationOffset")
            // checkAndNotify re-evaluates fully fresh each call (no cached/stale
            // schedule the way auto-join has), so nothing needs correcting here —
            // but it otherwise only runs on the ~60s calendar refresh timer, which
            // would leave a change sitting unapplied for up to a minute. Re-run it
            // immediately so the new threshold takes effect right away.
            NotificationManager.shared.checkAndNotify(
                meetings: CalendarManager.shared.meetings,
                offsets: enabledOffsets
            )
        }
    }

    /// How many minutes before start to auto-join. 0 = at start time.
    @Published var autoJoinOffset: Int {
        didSet {
            UserDefaults.standard.set(autoJoinOffset, forKey: "autoJoinOffset")
            AutoJoinManager.shared.rescheduleAllForOffsetChange()
        }
    }

    @Published var disabledCalendarIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledCalendarIds), forKey: "disabledCalendarIds") }
    }

    @Published var showAllEvents: Bool {
        didSet { UserDefaults.standard.set(showAllEvents, forKey: "showAllEvents") }
    }

    private init() {
        let d = UserDefaults.standard

        notificationOffset = d.object(forKey: "notificationOffset") != nil ? d.integer(forKey: "notificationOffset") : 10

        autoJoinOffset      = d.object(forKey: "autoJoinOffset") != nil ? d.integer(forKey: "autoJoinOffset") : 5
        disabledCalendarIds = Set(d.stringArray(forKey: "disabledCalendarIds") ?? [])
        showAllEvents       = d.bool(forKey: "showAllEvents")
    }

    var enabledOffsets: [Int] {
        notificationOffset > 0 ? [notificationOffset, 0] : [0]
    }
}
