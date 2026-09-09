import AppKit
import SwiftUI
import Combine

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

    private var colorIcon: NSImage?
    private var badgedIcon: NSImage?
    private var updateAvailableSubscription: AnyCancellable?

    private override init() {}

    func setup() {
        colorIcon = loadMenuBarIcon()
        if let colorIcon { badgedIcon = addUpdateBadge(to: colorIcon) }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Persists wherever the user Cmd-drags the icon to across launches —
        // without this, macOS has no memory of a manual reposition, so a
        // newly-hidden icon (crowded menu bar, notch) can't be fixed for good.
        item.autosaveName = "MisstingStatusItem"
        if let button = item.button {
            button.image = colorIcon ?? NSImage(systemSymbolName: "alarm", accessibilityDescription: "Missting")
            button.imageScaling = .scaleProportionallyDown
            button.title = ""
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        statusItem = item

        // Same ping as the Settings row, but visible without opening the popover
        // at all — a small dot on the menu bar icon itself, since that's the one
        // thing guaranteed to be glanced at, unlike a dialog that shows once and
        // is easy to miss on a background app.
        updateAvailableSubscription = UpdateManager.shared.$updateAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                guard let self, let button = self.statusItem?.button else { return }
                button.image = available ? (self.badgedIcon ?? self.colorIcon) : self.colorIcon
            }

        let pop = NSPopover()
        pop.behavior = .applicationDefined
        pop.animates = true

        let rootView = AnyView(
            MeetingListView()
                .environmentObject(CalendarManager.shared)
                .environmentObject(AutoJoinManager.shared)
                .environmentObject(SettingsManager.shared)
                .environmentObject(UpdateManager.shared)
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

    // MARK: - Popover

    /// Whether the meeting-list popover is currently open — checked by
    /// FloatingAlertManager so a reminder alert never renders stacked on top
    /// of it (both anchor near the same top-right corner of the screen).
    var isPopoverOpen: Bool { popover?.isShown ?? false }

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
        // No current event happens for assistive/automation-driven activation
        // (VoiceOver, accessibility tooling) — treat it as a normal left click
        // rather than silently doing nothing.
        if NSApp.currentEvent?.type == .rightMouseUp {
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

    /// Draws a small solid dot over the bottom-right corner of the icon — same
    /// blue as the Settings ping, with a thin white ring so it stays legible
    /// against both light and dark menu bars.
    private func addUpdateBadge(to base: NSImage) -> NSImage {
        let result = NSImage(size: base.size)
        result.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))

        let dotDiameter: CGFloat = 7
        let ringInset: CGFloat = 1
        let dotRect = NSRect(
            x: base.size.width - dotDiameter - 1,
            y: 0,
            width: dotDiameter,
            height: dotDiameter
        )

        NSColor.white.setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -ringInset, dy: -ringInset)).fill()

        NSColor(red: 0.31, green: 0.56, blue: 0.97, alpha: 1).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
