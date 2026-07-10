import Foundation

/// Persists which meetings the user has joined (clicked Join now or auto-joined)
/// and which they explicitly dismissed (clicked X on the floating alert).
/// Keyed on eventId + startDate so a rescheduled meeting always starts fresh.
final class JoinTracker {
    static let shared = JoinTracker()
    private let joinedKey    = "joinedMeetingIds"
    private let dismissedKey = "dismissedMeetingIds"

    private init() { cleanup() }

    // MARK: - Joined

    func markJoined(_ meeting: Meeting) {
        add(compoundKey(meeting), to: joinedKey)
    }

    func hasJoined(_ meeting: Meeting) -> Bool {
        list(joinedKey).contains(compoundKey(meeting))
    }

    func cancelJoin(_ meeting: Meeting) {
        remove(compoundKey(meeting), from: joinedKey)
    }

    // MARK: - Dismissed ("leave me alone about this meeting")

    func markDismissed(_ meeting: Meeting) {
        add(compoundKey(meeting), to: dismissedKey)
    }

    func isDismissed(_ meeting: Meeting) -> Bool {
        list(dismissedKey).contains(compoundKey(meeting))
    }

    func clearDismissed(_ meeting: Meeting) {
        remove(compoundKey(meeting), from: dismissedKey)
    }

    // MARK: - Private

    private func compoundKey(_ meeting: Meeting) -> String {
        "\(meeting.id)_\(Int(meeting.startDate.timeIntervalSince1970))"
    }

    // Stored as ordered arrays (oldest first) so pruning drops the oldest entries.
    private func list(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private func add(_ value: String, to key: String) {
        var items = list(key)
        guard !items.contains(value) else { return }
        items.append(value)
        UserDefaults.standard.set(items, forKey: key)
    }

    private func remove(_ value: String, from key: String) {
        var items = list(key)
        items.removeAll { $0 == value }
        UserDefaults.standard.set(items, forKey: key)
    }

    // Keep the lists from growing forever — prune oldest past 200 entries
    private func cleanup() {
        for key in [joinedKey, dismissedKey] {
            let items = list(key)
            if items.count > 200 {
                UserDefaults.standard.set(Array(items.suffix(200)), forKey: key)
            }
        }
    }
}
