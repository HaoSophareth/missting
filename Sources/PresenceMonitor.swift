import AppKit
import CoreGraphics
import Foundation

extension Notification.Name {
    /// Posted (on main) when the user comes back to the Mac after being away:
    /// unlock, display wake, screen saver stopped, or switching back to this account.
    static let userReturned = Notification.Name("userReturned")
}

/// Answers one question: is someone actually at this Mac right now?
///
/// Away = any of: Mac asleep (or just woke and hasn't shown the display yet),
/// screen locked, every display asleep, screen saver running, or another user
/// account active (fast user switching). Auto-join only opens a meeting link
/// while present, since an opened Forum link puts the student in class even
/// with nobody there.
final class PresenceMonitor {
    static let shared = PresenceMonitor()

    private var systemAsleep = false
    /// Set on sleep, cleared by the first real return signal (display wake,
    /// unlock, screen saver stop, session switch-back). Covers the moment right
    /// after wake, before the lock screen state has settled.
    private var needsReturnSignal = false
    private var lastWake: Date?
    private var displaysAsleepFlag = false
    private var screenSaverRunning = false
    private var screenLockedFlag = false
    private var sessionInactive = false

    private var returnCheckPending = false

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = true
            self?.needsReturnSignal = true
            self?.log("system will sleep")
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = false
            self?.lastWake = Date()
            self?.log("system did wake")
        }
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displaysAsleepFlag = true
            self?.log("displays asleep")
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.displaysAsleepFlag = false
            self?.returnSignal("displays woke")
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionInactive = true
            self?.log("session inactive (other user)")
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionInactive = false
            self?.returnSignal("session active again")
        }

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLockedFlag = true
            self?.log("screen locked")
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLockedFlag = false
            self?.returnSignal("screen unlocked")
        }
        dnc.addObserver(forName: .init("com.apple.screensaver.didstart"), object: nil, queue: .main) { [weak self] _ in
            self?.screenSaverRunning = true
            self?.log("screen saver started")
        }
        dnc.addObserver(forName: .init("com.apple.screensaver.didstop"), object: nil, queue: .main) { [weak self] _ in
            self?.screenSaverRunning = false
            self?.returnSignal("screen saver stopped")
        }
    }

    /// Starts observing. Call once at launch so no transition is missed.
    func start() { log("started, present=\(isPresent) [\(stateDescription)]") }

    // MARK: - State

    var isPresent: Bool { awayReason == nil }

    /// Why the user counts as away, or nil if present. Live checks are used
    /// alongside the notification flags so state is right even if Missting
    /// launched while already locked or dark.
    var awayReason: String? {
        if systemAsleep { return "system asleep" }
        // Only trusted briefly: if no return signal ever arrives, fall back to
        // the live lock/display/screen-saver checks rather than staying "away"
        // forever (which would make a student who is there miss class).
        if needsReturnSignal, let wake = lastWake, Date().timeIntervalSince(wake) < 10 {
            return "just woke, no return signal yet"
        }
        if sessionInactive || !sessionOnConsole { return "other user account active" }
        if screenLockedFlag || sessionScreenLocked { return "screen locked" }
        if screenSaverRunning || screenSaverProcessRunning { return "screen saver running" }
        if displaysAsleepFlag || allDisplaysAsleep { return "displays asleep" }
        return nil
    }

    var stateDescription: String { awayReason ?? "present" }

    private var sessionDict: [String: Any] {
        (CGSessionCopyCurrentDictionary() as? [String: Any]) ?? [:]
    }

    private var sessionScreenLocked: Bool {
        (sessionDict["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }

    private var sessionOnConsole: Bool {
        (sessionDict["kCGSSessionOnConsoleKey"] as? Bool) ?? true
    }

    private var screenSaverProcessRunning: Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.ScreenSaver.Engine"
        }
    }

    private var allDisplaysAsleep: Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }

    // MARK: - Return detection

    private func returnSignal(_ what: String) {
        needsReturnSignal = false
        log(what)
        // Let lock/display state settle (unlock and display wake often arrive
        // together), then announce once if the user is actually present.
        guard !returnCheckPending else { return }
        returnCheckPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.returnCheckPending = false
            self.log("return check: \(self.stateDescription)")
            if self.isPresent {
                NotificationCenter.default.post(name: .userReturned, object: nil)
            }
        }
    }

    /// Appends to ~/Library/Logs/Missting/presence.log (capped ~256 KB) so
    /// auto-join decisions can be checked after the fact.
    func log(_ msg: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Missting", isDirectory: true)
        let file = dir.appendingPathComponent("presence.log")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int,
           size > 256_000 {
            try? FileManager.default.removeItem(at: file)
        }
        let line = "\(ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime]))  \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(data); try? h.close()
        } else {
            try? data.write(to: file)
        }
    }
}
