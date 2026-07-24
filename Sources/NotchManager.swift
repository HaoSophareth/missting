import AppKit
import SwiftUI
import Combine

/// Renders Missting as a small pill anchored directly under the physical
/// notch (Dynamic-Island style) instead of a menu bar icon. Hovering or
/// clicking the pill expands it downward into the same meeting list used
/// by the classic menu bar popover.
final class NotchManager: NSObject, ObservableObject {
    static let shared = NotchManager()

    @Published fileprivate var isExpanded = false
    private var isPinned = false

    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var meetingsObservation: AnyCancellable?
    private var collapseTimer: Timer?
    private var eventMonitor: Any?
    private var spaceObserver: Any?

    private(set) var latestMeetings: [Meeting] = []
    private var colorIcon: NSImage?
    private var grayIcon: NSImage?

    /// The idle pill is wider than the physical notch cutout — a "shelf"
    /// hanging from it, not an invisible overlay — so it reads as a status
    /// indicator. The notch itself has no visible pixels (or is covered by
    /// the camera housing) — a screenshot shows content there, but on the
    /// real display it's physically invisible. So the pill must extend a
    /// few points *below* the notch for the icon to actually be seen;
    /// `peekHeight` is that minimum, kept small so it still reads as
    /// hugging the notch rather than a bulky rectangle.
    private static let idleSidePadding: CGFloat = 26
    private static let peekHeight: CGFloat = 22
    private(set) var idleSize: CGSize = .zero
    private(set) var notchHeight: CGFloat = 0

    private override init() { super.init() }

    // MARK: - Notch geometry

    static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.auxiliaryTopLeftArea != nil && $0.auxiliaryTopRightArea != nil }
    }

    static var hasNotch: Bool { notchedScreen != nil }

    private static func notchRect(on screen: NSScreen) -> NSRect? {
        guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NSRect(x: left.maxX, y: left.minY, width: width, height: left.height)
    }

    // MARK: - Setup / teardown

    func setup() {
        guard let screen = Self.notchedScreen, let notch = Self.notchRect(on: screen) else { return }

        notchHeight = notch.height
        idleSize = CGSize(width: notch.width + Self.idleSidePadding * 2,
                           height: notch.height + Self.peekHeight)

        colorIcon = loadIcon(gray: false)
        grayIcon  = loadIcon(gray: true)

        let p = NSPanel(
            contentRect: CGRect(origin: .zero, size: idleSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel      = true
        // .popUpMenu sits well above .statusBar — some apps (e.g. Arc) keep
        // their own transparent overlay across the whole menu bar strip at a
        // level just above .statusBar, which would otherwise eat our clicks.
        p.level                = .popUpMenu
        p.isOpaque             = false
        p.backgroundColor      = .clear
        p.hasShadow            = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior   = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.acceptsMouseMovedEvents = true

        let rootView = AnyView(
            NotchContentView()
                .environmentObject(self)
                .environmentObject(CalendarManager.shared)
                .environmentObject(AutoJoinManager.shared)
                .environmentObject(SettingsManager.shared)
        )
        // Deliberately no sizingOptions/preferredContentSize tracking and no
        // p.contentViewController assignment: both hand AppKit an automatic
        // "resize the window to match content" behavior that raced our own
        // frame updates unpredictably (observed: runaway growth, off-center
        // frames, transparent gaps). We are the SOLE authority on this
        // panel's frame — always an explicit, one-shot measure-then-setFrame,
        // never a reactive observer loop.
        let hc = NSHostingController(rootView: rootView)
        p.contentView = hc.view
        hostingController = hc
        panel = p

        // Re-measure when the meeting list's content actually changes (new
        // data from a fetch) while expanded — safe from feedback loops since
        // this fires from CalendarManager's own publisher, never from our
        // own frame changes.
        meetingsObservation = CalendarManager.shared.$meetings
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.isExpanded else { return }
                self.remeasureAndApply(animated: true)
            }

        p.orderFrontRegardless()
        applyFrame(for: idleSize, animated: false)
    }

    func teardown() {
        stopMonitoring()
        collapseTimer?.invalidate(); collapseTimer = nil
        meetingsObservation = nil
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        isExpanded = false
        isPinned = false
    }

    // MARK: - Status

    func updateStatusText(_ meetings: [Meeting]) {
        latestMeetings = meetings
    }

    var hasUpcomingMeeting: Bool {
        let now = Date()
        if latestMeetings.contains(where: { $0.isInProgress && $0.joinURL != nil }) { return true }
        if CallDetector.shared.isInCall { return true }
        let cal = Calendar.current
        let endOfToday    = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        let sixAmTomorrow = cal.date(bySettingHour: 6, minute: 0, second: 0,
                                     of: cal.date(byAdding: .day, value: 1, to: now)!)!
        return latestMeetings.contains {
            $0.joinURL != nil && $0.startDate > now &&
            ($0.startDate <= endOfToday || $0.startDate < sixAmTomorrow)
        }
    }

    var currentIcon: NSImage? { hasUpcomingMeeting ? colorIcon : grayIcon }

    // MARK: - Expand / collapse

    fileprivate func expand(pinned: Bool) {
        if pinned { isPinned = true }
        guard !isExpanded else {
            if pinned { startMonitoring() }
            return
        }
        collapseTimer?.invalidate()
        isExpanded = true
        if pinned { startMonitoring() }
        // One explicit measurement after SwiftUI lays out the expanded
        // content — not an ongoing observer, so there's nothing to race.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.isExpanded else { return }
            self.remeasureAndApply(animated: true)
        }
    }

    fileprivate func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        isPinned = false
        stopMonitoring()
        applyFrame(for: idleSize, animated: true)
    }

    fileprivate func hoverEntered() {
        collapseTimer?.invalidate()
        guard !isExpanded else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.expand(pinned: false)
        }
    }

    fileprivate func hoverExited() {
        guard isExpanded, !isPinned else { return }
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.collapse()
        }
    }

    // MARK: - Frame

    private func applyFrame(for size: CGSize, animated: Bool) {
        guard let panel, let screen = Self.notchedScreen, let notch = Self.notchRect(on: screen) else { return }
        let centerX = notch.midX
        let topY    = notch.maxY
        let newFrame = NSRect(x: centerX - size.width / 2, y: topY - size.height,
                               width: size.width, height: size.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true)
        }
    }

    /// Measures the hosting view's natural size right now (a plain NSView
    /// fittingSize computation — not a reactive/observed value) and applies
    /// it as the panel's frame in one shot.
    private func remeasureAndApply(animated: Bool) {
        guard let hostingController else { return }
        let size = hostingController.view.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        applyFrame(for: size, animated: animated)
    }

    // MARK: - Auto-close (pinned state)

    private func startMonitoring() {
        stopMonitoring()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.collapse()
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.collapse()
        }
    }

    private func stopMonitoring() {
        if let m = eventMonitor { NSEvent.removeMonitor(m); eventMonitor = nil }
        if let o = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            spaceObserver = nil
        }
    }

    private func loadIcon(gray: Bool) -> NSImage? {
        guard let source = gray ? AppResources.sunflowerGray() : AppResources.sunflower() else { return nil }
        let iconSize: CGFloat = 16
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

// MARK: - Content view

private struct NotchContentView: View {
    @EnvironmentObject private var notch: NotchManager

    var body: some View {
        VStack(spacing: 0) {
            // The true physical notch strip: no visible pixels on real
            // hardware (screenshots show it, the actual display doesn't) —
            // kept empty so nothing meaningful ever renders there.
            Color.black.frame(height: notch.notchHeight)
            if notch.isExpanded {
                MeetingListView()
            } else {
                NotchIdleView()
            }
        }
        .background(Color.black)
        .clipShape(BottomRoundedRect(radius: 14))
        .onHover { hovering in
            if hovering { notch.hoverEntered() } else { notch.hoverExited() }
        }
    }
}

/// The idle pill — deliberately sized to notch.idleSize (wider/taller than
/// the true notch cutout) via an explicit frame, not maxWidth/.infinity.
/// An unbounded frame has no well-defined "ideal size", and NotchManager
/// measures this view's fittingSize to size the actual panel — an
/// unbounded frame here would report a tiny/undefined fitting size instead
/// of the pill dimensions we actually want.
private struct NotchIdleView: View {
    @EnvironmentObject private var notch: NotchManager
    @State private var tick = 0

    var body: some View {
        Button { notch.expand(pinned: true) } label: {
            HStack {
                if let icon = notch.currentIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
            }
            .frame(width: notch.idleSize.width, height: notch.idleSize.height - notch.notchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
    }
}

/// A rectangle flush at the top (hugging the true screen edge, like the
/// notch itself) with only the bottom two corners rounded — the "shelf"
/// silhouette, in both idle and expanded states.
private struct BottomRoundedRect: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                           control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                           control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
