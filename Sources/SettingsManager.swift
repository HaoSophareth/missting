import Foundation

final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var alert30: Bool {
        didSet { UserDefaults.standard.set(alert30, forKey: "alert30") }
    }
    @Published var alert15: Bool {
        didSet { UserDefaults.standard.set(alert15, forKey: "alert15") }
    }
    @Published var alert10: Bool {
        didSet { UserDefaults.standard.set(alert10, forKey: "alert10") }
    }
    @Published var alert5: Bool {
        didSet { UserDefaults.standard.set(alert5, forKey: "alert5") }
    }
    @Published var alertAtStart: Bool {
        didSet { UserDefaults.standard.set(alertAtStart, forKey: "alertAtStart") }
    }

    /// How many minutes before the meeting start time to auto-join. Default 0 (at start).
    @Published var autoJoinOffset: Int {
        didSet { UserDefaults.standard.set(autoJoinOffset, forKey: "autoJoinOffset") }
    }

    /// Calendar IDs the user has hidden from Missting.
    @Published var disabledCalendarIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledCalendarIds), forKey: "disabledCalendarIds")
        }
    }

    private init() {
        let d = UserDefaults.standard
        if d.object(forKey: "settingsInitialized") == nil {
            d.set(true, forKey: "alert30")
            d.set(true, forKey: "alert15")
            d.set(true, forKey: "alert10")
            d.set(true, forKey: "alert5")
            d.set(true, forKey: "alertAtStart")
            d.set(true, forKey: "settingsInitialized")
        }
        if d.object(forKey: "alert15Initialized") == nil {
            d.set(true, forKey: "alert15")
            d.set(true, forKey: "alert15Initialized")
        }
        alert30        = d.bool(forKey: "alert30")
        alert15        = d.bool(forKey: "alert15")
        alert10        = d.bool(forKey: "alert10")
        alert5         = d.bool(forKey: "alert5")
        alertAtStart   = d.bool(forKey: "alertAtStart")
        autoJoinOffset = d.object(forKey: "autoJoinOffset") != nil
                         ? d.integer(forKey: "autoJoinOffset") : 0
        disabledCalendarIds = Set(d.stringArray(forKey: "disabledCalendarIds") ?? [])
    }

    var enabledOffsets: [Int] {
        var offsets: [Int] = []
        if alert30 { offsets.append(30) }
        if alert15 { offsets.append(15) }
        if alert10 { offsets.append(10) }
        if alert5  { offsets.append(5)  }
        offsets.append(0)
        return offsets
    }
}
