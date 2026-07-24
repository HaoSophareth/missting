import Foundation

/// Decides whether Missting lives in the menu bar or in the notch, and owns
/// whichever presenter is currently active so callers (CalendarManager, wake
/// handlers, etc.) don't need to know which mode is active.
final class DisplayCoordinator {
    static let shared = DisplayCoordinator()

    private init() {}

    private(set) var activeMode: SettingsManager.DisplayMode = .menuBar

    /// The mode actually in effect — falls back to the menu bar when notch
    /// mode is selected but this Mac has no physical notch to anchor to.
    var effectiveMode: SettingsManager.DisplayMode {
        let preferred = SettingsManager.shared.displayMode
        if preferred == .notch, !NotchManager.hasNotch { return .menuBar }
        return preferred
    }

    func activate() {
        activeMode = effectiveMode
        switch activeMode {
        case .menuBar: MenuBarManager.shared.setup()
        case .notch:   NotchManager.shared.setup()
        }
    }

    /// Called after the user flips the Settings toggle — tears down whichever
    /// presenter is running and brings up the other, live, without a restart.
    func switchIfNeeded() {
        let newMode = effectiveMode
        guard newMode != activeMode else { return }
        switch activeMode {
        case .menuBar: MenuBarManager.shared.teardown()
        case .notch:   NotchManager.shared.teardown()
        }
        activeMode = newMode
        switch newMode {
        case .menuBar: MenuBarManager.shared.setup()
        case .notch:   NotchManager.shared.setup()
        }
    }

    func updateStatusText(_ meetings: [Meeting]) {
        switch activeMode {
        case .menuBar: MenuBarManager.shared.updateStatusText(meetings)
        case .notch:   NotchManager.shared.updateStatusText(meetings)
        }
    }
}
