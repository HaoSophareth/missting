import AppKit
import SwiftUI

final class MenuBarManager: NSObject {
    static let shared = MenuBarManager()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: NSHostingController<AnyView>?
    private var eventMonitor: Any?
    private var spaceObserver: Any?
    private var sizeObservation: NSKeyValueObservation?
    private var pendingSize: CGSize = .zero
    private var resizeTimer: Timer?
    private var statusRefreshTimer: Timer?
    private var latestMeetings: [Meeting] = []

    private override init() {}

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let icon = loadMenuBarIcon() {
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "alarm",
                                       accessibilityDescription: "Missting")
            }
            // Handle both left and right clicks
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        statusItem = item

        // Refresh the status text every 30 seconds so countdowns stay accurate
        statusRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.applyStatusText(self.latestMeetings)
        }

        let pop = NSPopover()
        pop.behavior = .applicationDefined
        pop.animates = true

        let rootView = AnyView(
            MeetingListView()
                .environmentObject(CalendarManager.shared)
                .environmentObject(AutoJoinManager.shared)
                .environmentObject(SettingsManager.shared)
        )
        let hc = NSHostingController(rootView: rootView)

        // sizingOptions = .preferredContentSize makes the hosting controller
        // continuously compute preferredContentSize from the SwiftUI content's
        // ideal size (not the frame), so it correctly shrinks AND grows.
        if #available(macOS 13.0, *) {
            hc.sizingOptions = [.preferredContentSize]
        }

        pop.contentViewController = hc
        pop.contentSize = hc.preferredContentSize
        hostingController = hc
        popover = pop

        // KVO: debounced so accordion animations (0.18 s) complete before
        // the popover resizes — eliminates mid-animation flicker.
        sizeObservation = hc.observe(\.preferredContentSize, options: .new) { [weak self] _, change in
            guard let size = change.newValue, size.width > 0, size.height > 0 else { return }
            DispatchQueue.main.async { [weak self] in
                self?.scheduleResize(to: size)
            }
        }
    }

    // MARK: - Status text

    func updateStatusText(_ meetings: [Meeting]) {
        latestMeetings = meetings
        applyStatusText(meetings)
    }

    private func applyStatusText(_ meetings: [Meeting]) {
        guard let button = statusItem?.button else { return }
        let now = Date()

        // 1. In-progress meeting
        if meetings.contains(where: { $0.isInProgress }) {
            button.title = " · in progress"
            return
        }

        // 2. Next upcoming meeting — only show if it's today or early morning (before 6am tomorrow)
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let sixAmTomorrow = cal.date(bySettingHour: 6, minute: 0, second: 0,
                                     of: cal.date(byAdding: .day, value: 1, to: now)!)!

        if let next = meetings
            .filter({ $0.startDate > now && ($0.startDate <= endOfToday || $0.startDate < sixAmTomorrow) })
            .sorted(by: { $0.startDate < $1.startDate })
            .first {
            let mins = next.minsUntilStart
            let timeStr: String
            if mins <= 1 {
                timeStr = "now"
            } else if mins < 60 {
                timeStr = "\(mins)m"
            } else {
                let h = mins / 60
                let rem = mins % 60
                timeStr = rem == 0 ? "\(h)h" : "\(h)h \(rem)m"
            }
            button.title = " in \(timeStr)"
            return
        }

        // 3. No meetings today — show a randomised "done for the day" message
        button.title = " \(donForTheDayMessage())"
    }

    private func donForTheDayMessage() -> String {
        let messages = [
            "You're free!",
            "That's a wrap!",
            "Go touch grass",
            "All clear today",
            "No more meetings",
            "You survived today",
            "Clear skies ahead",
            "Rest mode: on",
            "Nothing. Enjoy it.",
            "You earned this",
        ]
        // Seed by day so it stays consistent within a day but changes daily
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return messages[dayOfYear % messages.count]
    }

    /// Extracts the short identifier from a meeting title.
    /// "CS114 Session 22 - ..." → "CS114"
    /// "180DC – Rim + Phareth" → "180DC"
    private func shortTitle(_ title: String) -> String {
        title.components(separatedBy: .whitespaces).first ?? title
    }

    // MARK: - Popover

    func showPopover() {
        guard let button = statusItem?.button, let pop = popover, !pop.isShown else { return }
        // Apply correct size immediately before showing
        if let hc = hostingController {
            let s = hc.preferredContentSize
            if s.width > 0, s.height > 0 { pop.contentSize = s }
        }
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        startMonitoring()
    }

    func closePopover() {
        popover?.performClose(nil)
        stopMonitoring()
    }

    // MARK: - Resize

    private func scheduleResize(to size: CGSize) {
        pendingSize = size
        resizeTimer?.invalidate()
        resizeTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: false) { [weak self] _ in
            guard let self, self.pendingSize.width > 0 else { return }
            self.popover?.contentSize = self.pendingSize
        }
    }

    // MARK: - Click handling

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showQuitMenu()
        } else {
            guard let pop = popover else { return }
            if pop.isShown { closePopover() } else { showPopover() }
        }
    }

    private func showQuitMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Missting",
                                action: #selector(NSApp.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Clear menu so future left-clicks still open the popover
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    // MARK: - Auto-close monitors

    private func startMonitoring() {
        stopMonitoring()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.closePopover()
        }

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func stopMonitoring() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        if let o = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            spaceObserver = nil
        }
    }

    private func loadMenuBarIcon() -> NSImage? {
        guard let source = AppResources.sunflower() else { return nil }

        let iconSize: CGFloat = 22
        let padding: CGFloat = 2
        let total = iconSize + padding * 2
        let totalSize = NSSize(width: total, height: total)

        let result = NSImage(size: totalSize)
        result.lockFocus()

        if let ctx = NSGraphicsContext.current?.cgContext {
            // Subtle dark shadow so the flower pops without glowing
            ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 2,
                          color: NSColor.black.withAlphaComponent(0.55).cgColor)
        }

        source.draw(in: NSRect(x: padding, y: padding, width: iconSize, height: iconSize))
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
