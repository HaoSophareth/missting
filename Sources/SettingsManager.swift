import Foundation

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    /// Where Missting's status + meeting list live.
    enum DisplayMode: String, CaseIterable {
        case notch
        case menuBar
    }

    @Published var displayMode: DisplayMode {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "displayMode") }
    }

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

    @Published var showAllEvents: Bool {
        didSet { UserDefaults.standard.set(showAllEvents, forKey: "showAllEvents") }
    }

    private init() {
        let d = UserDefaults.standard

        displayMode = d.string(forKey: "displayMode").flatMap(DisplayMode.init(rawValue:)) ?? .menuBar

        notificationOffset = d.object(forKey: "notificationOffset") != nil ? d.integer(forKey: "notificationOffset") : 10

        autoJoinOffset      = d.object(forKey: "autoJoinOffset") != nil ? d.integer(forKey: "autoJoinOffset") : 5
        disabledCalendarIds = Set(d.stringArray(forKey: "disabledCalendarIds") ?? [])
        showAllEvents       = d.bool(forKey: "showAllEvents")
    }

    var enabledOffsets: [Int] {
        notificationOffset > 0 ? [notificationOffset, 0] : [0]
    }
}
