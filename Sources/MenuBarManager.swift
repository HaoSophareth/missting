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
    private var iconRefreshTimer: Timer?
    private var latestMeetings: [Meeting] = []

    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    private override init() {}

    func setup() {
        colorIcon = loadMenuBarIcon(gray: false)
        grayIcon  = loadMenuBarIcon(gray: true)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = grayIcon ?? NSImage(systemSymbolName: "alarm", accessibilityDescription: "Missting")
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        statusItem = item

        iconRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.applyStatusIcon(self.latestMeetings)
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

    // MARK: - Icon state

    func updateStatusText(_ meetings: [Meeting]) {
        latestMeetings = meetings
        applyStatusIcon(meetings)
    }

    private func applyStatusIcon(_ meetings: [Meeting]) {
        guard let button = statusItem?.button else { return }
        let now = Date()
        let cal = Calendar.current

        let hasMeeting: Bool
        if meetings.contains(where: { $0.isInProgress && $0.joinURL != nil }) {
            hasMeeting = true
        } else if CallDetector.shared.isInCall {
            hasMeeting = true
        } else {
            let endOfToday    = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
            let sixAmTomorrow = cal.date(bySettingHour: 6, minute: 0, second: 0,
                                         of: cal.date(byAdding: .day, value: 1, to: now)!)!
            hasMeeting = meetings.contains {
                $0.joinURL != nil && $0.startDate > now &&
                ($0.startDate <= endOfToday || $0.startDate < sixAmTomorrow)
            }
        }

        button.image = hasMeeting ? colorIcon : grayIcon
        button.title = ""
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
        let updateItem = NSMenuItem(title: "Check for Updates…",
                                    action: #selector(checkForUpdates),
                                    keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
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

    @objc private func checkForUpdates() {
        (NSApp.delegate as? AppDelegate)?.updaterController.checkForUpdates(nil)
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

    private func loadMenuBarIcon(gray: Bool) -> NSImage? {
        guard let source = gray ? AppResources.sunflowerGray() : AppResources.sunflower() else { return nil }
        let iconSize: CGFloat = 18
        let size = NSSize(width: iconSize, height: iconSize)

        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
