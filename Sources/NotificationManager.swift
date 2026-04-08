import UserNotifications
import AppKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let center      = UNUserNotificationCenter.current()
    private let joinId      = "JOIN"
    private let categoryId  = "MEETING"

    // Tracks which meeting+offset combos we've already notified about (persisted across launches)
    private var shown: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "shownNotifs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "shownNotifs") }
    }

    private override init() {
        super.init()
        center.delegate = self
        let joinAction = UNNotificationAction(identifier: joinId, title: "Join now", options: .foreground)
        let category   = UNNotificationCategory(identifier: categoryId, actions: [joinAction], intentIdentifiers: [])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Called every minute from CalendarManager. Fires a notification the first time
    /// a meeting crosses each enabled threshold (30m, 10m, 5m, 0m).
    /// Called on system wake — shows a floating alert for any meeting currently in progress.
    func alertInProgressMeetings(_ meetings: [Meeting]) {
        DispatchQueue.main.async {
            for meeting in meetings {
                guard meeting.isInProgress,
                      !meeting.isPending,
                      !meeting.isDeclined,
                      meeting.joinURL != nil,
                      !JoinTracker.shared.hasJoined(meeting.id),
                      !AutoJoinManager.shared.isScheduled(meeting.id) else { continue }
                FloatingAlertManager.shared.present(meeting: meeting)
            }
        }
    }

    func checkAndNotify(meetings: [Meeting], offsets: [Int]) {
        var seenNow = shown

        for meeting in meetings {
            // Never notify for pending or declined invites
            if meeting.isPending || meeting.isDeclined { continue }

            // Skip if user already joined or auto-join is scheduled
            if JoinTracker.shared.hasJoined(meeting.id) || AutoJoinManager.shared.isScheduled(meeting.id) { continue }

            let mins = meeting.minsUntilStart

            // Clean up old keys for meetings that have ended
            if meeting.endDate < Date() {
                offsets.forEach { seenNow.remove("\(meeting.id)-\($0)") }
                continue
            }

            for offset in offsets {
                guard mins <= offset else { continue } // not yet at this threshold
                let key = "\(meeting.id)-\(offset)"
                guard !seenNow.contains(key) else { continue } // already notified

                fireNotification(for: meeting, offset: offset)
                seenNow.insert(key)
            }
        }

        shown = seenNow
    }

    func cancelNotifications(for eventId: String) {
        // Remove in-memory dedup keys so if rescheduled they can fire again
        var s = shown
        s = s.filter { !$0.hasPrefix("\(eventId)-") }
        shown = s
        // Also remove any banners already delivered
        center.removeDeliveredNotifications(withIdentifiers:
            [30, 15, 10, 5, 0].map { "\(eventId)-\($0)" })
    }

    // MARK: - Private

    private func fireNotification(for meeting: Meeting, offset: Int) {
        let content = UNMutableNotificationContent()
        content.title = meeting.title
        content.body  = offset == 0 ? "Starting now" : "Starting in \(offset) minute\(offset == 1 ? "" : "s")"
        content.sound = .default
        content.categoryIdentifier = categoryId
        if let url = meeting.joinURL {
            content.userInfo = ["joinURL": url.absoluteString]
        }

        // 1-second delay trigger (nil trigger is unreliable on unsigned macOS apps)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "\(meeting.id)-\(offset)",
                                            content: content,
                                            trigger: trigger)
        center.add(request, withCompletionHandler: nil)

        // Show the floating alert only if not already scheduled for auto-join
        if !AutoJoinManager.shared.isScheduled(meeting.id) {
            FloatingAlertManager.shared.present(meeting: meeting)
        }
    }

    // MARK: - Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == joinId,
           let urlStr = response.notification.request.content.userInfo["joinURL"] as? String,
           let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
            FloatingAlertManager.shared.dismiss()
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
