import Foundation

/// Persists which meeting IDs the user has joined (clicked Join now or auto-joined).
/// Past meetings not in this set are shown as "Missed".
final class JoinTracker {
    static let shared = JoinTracker()
    private let key = "joinedMeetingIds"

    private init() { cleanup() }

    func markJoined(_ id: String) {
        var joined = all()
        joined.insert(id)
        UserDefaults.standard.set(Array(joined), forKey: key)
    }

    func hasJoined(_ id: String) -> Bool {
        all().contains(id)
    }

    private func all() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    // Keep the list from growing forever — prune after 200 entries
    private func cleanup() {
        var joined = UserDefaults.standard.stringArray(forKey: key) ?? []
        if joined.count > 200 { joined = Array(joined.suffix(200)) }
        UserDefaults.standard.set(joined, forKey: key)
    }
}
