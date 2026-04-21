import Foundation

/// Persists which meetings the user has joined (clicked Join now or auto-joined).
/// Keyed on eventId + startDate so a rescheduled meeting always starts fresh.
final class JoinTracker {
    static let shared = JoinTracker()
    private let storageKey = "joinedMeetingIds"

    private init() { cleanup() }

    func markJoined(_ meeting: Meeting) {
        var joined = all()
        joined.insert(compoundKey(meeting))
        UserDefaults.standard.set(Array(joined), forKey: storageKey)
    }

    func hasJoined(_ meeting: Meeting) -> Bool {
        all().contains(compoundKey(meeting))
    }

    private func compoundKey(_ meeting: Meeting) -> String {
        "\(meeting.id)_\(Int(meeting.startDate.timeIntervalSince1970))"
    }

    private func all() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
    }

    // Keep the list from growing forever — prune after 200 entries
    private func cleanup() {
        var joined = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        if joined.count > 200 { joined = Array(joined.suffix(200)) }
        UserDefaults.standard.set(joined, forKey: storageKey)
    }
}
