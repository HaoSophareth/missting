import AppKit

/// Centralises resource loading with two fallback strategies so images load
/// correctly whether the app is run from Xcode, a build script, or a user install.
enum AppResources {

    static func sunflower() -> NSImage? {
        loadImage(name: "sunflower", ext: "png")
    }

    // MARK: - Private

    private static func loadImage(name: String, ext: String) -> NSImage? {
        // Strategy 1: standard Bundle.main lookup (works in most cases)
        if let url = Bundle.main.url(forResource: name, withExtension: ext),
           let img = NSImage(contentsOf: url) {
            return img
        }
        // Strategy 2: explicit path from bundle URL (more reliable for
        // SPM executables where Bundle.main resource lookup can fail)
        let direct = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/\(name).\(ext)")
        if let img = NSImage(contentsOfFile: direct.path) {
            return img
        }
        return nil
    }
}
