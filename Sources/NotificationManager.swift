import AppKit

final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    // Tracks which meeting+offset combos we've already notified about (persisted across launches)
    private var shown: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "shownNotifs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "shownNotifs") }
    }

    private override init() { super.init() }

    /// Called on system wake — shows a floating alert for any meeting currently in progress
    /// that the user hasn't joined, dismissed, or scheduled for auto-join.
    func alertInProgressMeetings(_ meetings: [Meeting]) {
        DispatchQueue.main.async {
            for meeting in meetings {
                guard meeting.isInProgress,
                      !meeting.isPending,
                      !meeting.isDeclined,
                      !JoinTracker.shared.hasJoined(meeting),
                      !JoinTracker.shared.isDismissed(meeting),
                      !AutoJoinManager.shared.isScheduled(meeting.id) else { continue }
                FloatingAlertManager.shared.present(meeting: meeting)
            }
        }
    }

    /// Called after every calendar fetch (~1/min). Fires a notification the first time
    /// a meeting crosses each enabled threshold, but only while the threshold is still
    /// fresh — after sleep/wake we skip stale "Starting in X minutes" banners and show
    /// a single in-progress alert instead.
    func checkAndNotify(meetings: [Meeting], offsets: [Int]) {
        var seenNow = shown

        for meeting in meetings {
            // Never notify for pending or declined events
            if meeting.isPending || meeting.isDeclined { continue }

            // Skip if user already joined, dismissed the alert, or auto-join is scheduled
            if JoinTracker.shared.hasJoined(meeting)
                || JoinTracker.shared.isDismissed(meeting)
                || AutoJoinManager.shared.isScheduled(meeting.id) { continue }

            let mins = meeting.minsUntilStart

            for offset in offsets {
                guard mins <= offset else { continue }       // not yet at this threshold
                guard offset - mins <= 2 else { continue }   // crossed too long ago — stale
                let key = "\(meeting.id)-\(offset)"
                guard !seenNow.contains(key) else { continue } // already notified

                fireNotification(for: meeting, offset: offset)
                seenNow.insert(key)
            }

            // App launched or woke mid-meeting and every threshold went stale —
            // show one in-progress alert instead of outdated countdown banners.
            if meeting.isInProgress {
                let key = "\(meeting.id)-inprogress"
                let sawAnyOffset = offsets.contains { seenNow.contains("\(meeting.id)-\($0)") }
                if !sawAnyOffset, !seenNow.contains(key) {
                    seenNow.insert(key)
                    FloatingAlertManager.shared.present(meeting: meeting)
                }
            }
        }

        // Ended meetings are filtered out before we ever see them, so dedup keys
        // are never cleaned up per-meeting — prune to current meetings once large.
        if seenNow.count > 200 {
            let activeIds = meetings.map(\.id)
            seenNow = seenNow.filter { key in activeIds.contains { key.hasPrefix("\($0)-") } }
        }

        shown = seenNow
    }

    func cancelNotifications(for eventId: String) {
        // Remove dedup keys so if rescheduled they can fire again
        let keys = shown.filter { $0.hasPrefix("\(eventId)-") }
        guard !keys.isEmpty else { return }
        shown = shown.subtracting(keys)
    }

    // MARK: - Private

    private func fireNotification(for meeting: Meeting, offset: Int) {
        // Show the floating alert only if not already scheduled for auto-join
        if !AutoJoinManager.shared.isScheduled(meeting.id) {
            FloatingAlertManager.shared.present(meeting: meeting)
        }
    }
}
