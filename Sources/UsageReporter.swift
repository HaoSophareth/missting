import Foundation

/// Sends a single anonymous ping roughly once a day so we can see how many
/// installs of Missting are actually active. The id is a random UUID
/// generated on-device and stored locally — never the signed-in Google
/// account, email, or anything from calendar data. Fire-and-forget: failures
/// are silently ignored and never surfaced to the user.
enum UsageReporter {
    private static let endpoint = URL(string: "https://www.phareth.com/api/missting-ping")!
    private static let minInterval: TimeInterval = 20 * 60 * 60

    static func pingIfNeeded() {
        let d = UserDefaults.standard
        let now = Date()
        if let last = d.object(forKey: "lastUsagePingDate") as? Date,
           now.timeIntervalSince(last) < minInterval {
            return
        }
        d.set(now, forKey: "lastUsagePingDate")

        let id: String
        if let existing = d.string(forKey: "usageDeviceID") {
            id = existing
        } else {
            id = UUID().uuidString
            d.set(id, forKey: "usageDeviceID")
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        var comps = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "v", value: version),
        ]
        guard let url = comps.url else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request).resume()
    }
}
