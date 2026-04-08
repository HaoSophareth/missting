import AppKit
import SwiftUI

final class FloatingAlertManager {
    static let shared = FloatingAlertManager()

    // One entry per active alert: (panel, timer, meetingId)
    private struct Entry {
        let panel: NSPanel
        let timer: Timer
        let meetingId: String
    }
    private var entries: [Entry] = []

    private let panelWidth: CGFloat = 348  // 340 content + 4 padding each side
    private let gap: CGFloat = 4           // vertical gap between stacked alerts
    private let marginRight: CGFloat = 8
    private let marginTop: CGFloat = 4     // just below menu bar

    private init() {}

    func present(meeting: Meeting) {
        DispatchQueue.main.async { self._present(meeting: meeting) }
    }

    private func _present(meeting: Meeting) {
        // Don't show a duplicate for the same meeting
        if entries.contains(where: { $0.meetingId == meeting.id }) { return }

        let activeScreen = currentScreen()

        let hostingView = NSHostingView(
            rootView: FloatingAlertView(
                meeting: meeting,
                onJoin: { [weak self] in
                    if let url = meeting.joinURL { NSWorkspace.shared.open(url) }
                    JoinTracker.shared.markJoined(meeting.id)
                    self?.dismiss(meetingId: meeting.id)
                },
                onDismiss: { [weak self] in self?.dismiss(meetingId: meeting.id) }
            )
            .environmentObject(AutoJoinManager.shared)
        )

        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: 200)
        let fittingHeight = hostingView.fittingSize.height

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: fittingHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel             = true
        p.level                       = .statusBar
        p.isMovableByWindowBackground = true
        p.isOpaque                    = false
        p.backgroundColor             = .clear
        p.hasShadow                   = false
        p.contentView                 = hostingView
        p.isReleasedWhenClosed        = false
        p.collectionBehavior          = [.canJoinAllSpaces, .fullScreenAuxiliary]

        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = CGColor.clear

        // Stack below any existing panels
        let x = activeScreen.visibleFrame.maxX - panelWidth - marginRight
        let topY = activeScreen.visibleFrame.maxY - marginTop
        let stackedHeight = entries.reduce(0.0) { $0 + $1.panel.frame.height + gap }
        let y = topY - fittingHeight - stackedHeight
        p.setFrameOrigin(NSPoint(x: x, y: y))

        p.orderFrontRegardless()

        let timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            self?.dismiss(meetingId: meeting.id)
        }
        entries.append(Entry(panel: p, timer: timer, meetingId: meeting.id))
    }

    func dismiss(meetingId: String) {
        DispatchQueue.main.async {
            guard let idx = self.entries.firstIndex(where: { $0.meetingId == meetingId }) else { return }
            let entry = self.entries.remove(at: idx)
            entry.timer.invalidate()
            entry.panel.close()
        }
    }

    // Dismiss all (used externally e.g. from auto-join)
    func dismiss() {
        DispatchQueue.main.async {
            self.entries.forEach { $0.timer.invalidate(); $0.panel.close() }
            self.entries.removeAll()
        }
    }

    private func currentScreen() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
