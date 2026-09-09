import Sparkle

/// Owns the Sparkle updater and tracks whether a newer version is currently
/// known to be available, so Settings can show a persistent status/ping
/// instead of relying on people to notice — and dismiss, and forget — a modal
/// dialog that only appears once per check.
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published private(set) var updateAvailable = false
    @Published private(set) var isChecking = false

    /// Sparkle auto-updater — checks the appcast feed on a schedule and
    /// installs signed updates from GitHub Releases. Implicitly-unwrapped
    /// because SPUUpdater's delegate can only be set at construction, which
    /// needs `self` fully initialized as an NSObject first (super.init()
    /// below) — a plain non-optional `let` set before that isn't allowed.
    private(set) var controller: SPUStandardUpdaterController!

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        isChecking = true
        controller.checkForUpdates(nil)
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.updateAvailable = true
        }
    }

    // The one delegate callback Sparkle guarantees fires when a check concludes,
    // for every outcome — found, not found, a network/server error, or the user
    // cancelling. didFindValidUpdate/updaterDidNotFindUpdate alone don't cover
    // every real outcome (a hard error hits neither), which is exactly how
    // isChecking got stuck true forever with a spinner that never resolved.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        DispatchQueue.main.async {
            self.isChecking = false
            if let nsError = error as NSError?,
               nsError.domain == SUSparkleErrorDomain,
               nsError.code == SUError.noUpdateError.rawValue {
                self.updateAvailable = false
            }
            // Any other error: leave updateAvailable as it was — a network/server
            // failure doesn't actually tell us whether one exists, so don't
            // claim "you're up to date" when we don't know that.
        }
    }
}
