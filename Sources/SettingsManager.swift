import Foundation

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    /// Minutes before a meeting to send a notification.
    @Published var notificationOffset: Int {
        didSet { UserDefaults.standard.set(notificationOffset, forKey: "notificationOffset") }
    }

    /// How many minutes before start to auto-join. 0 = at start time.
    @Published var autoJoinOffset: Int {
        didSet { UserDefaults.standard.set(autoJoinOffset, forKey: "autoJoinOffset") }
    }

    @Published var disabledCalendarIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(disabledCalendarIds), forKey: "disabledCalendarIds") }
    }

    /// Calendar IDs we've already picked a one-time enabled/disabled default
    /// for (see `CalendarManager.applyDefaultsForNewCalendars`), so a
    /// calendar the user re-enables in Settings doesn't get defaulted off
    /// again on the next fetch.
    @Published var seenCalendarIds: Set<String> {
        didSet { UserDefaults.standard.set(Array(seenCalendarIds), forKey: "seenCalendarIds") }
    }

    @Published var showAllEvents: Bool {
        didSet { UserDefaults.standard.set(showAllEvents, forKey: "showAllEvents") }
    }

    private init() {
        let d = UserDefaults.standard

        notificationOffset = d.object(forKey: "notificationOffset") != nil ? d.integer(forKey: "notificationOffset") : 10

        autoJoinOffset      = d.object(forKey: "autoJoinOffset") != nil ? d.integer(forKey: "autoJoinOffset") : 5
        disabledCalendarIds = Set(d.stringArray(forKey: "disabledCalendarIds") ?? [])
        seenCalendarIds     = Set(d.stringArray(forKey: "seenCalendarIds") ?? [])
        showAllEvents       = d.bool(forKey: "showAllEvents")
    }

    var enabledOffsets: [Int] {
        notificationOffset > 0 ? [notificationOffset, 0] : [0]
    }
}
