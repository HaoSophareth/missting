import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcomePanel: NSPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
        NotificationManager.shared.requestAuthorization()
        MenuBarManager.shared.setup()
        CalendarManager.shared.startRefreshingIfSignedIn()

        // Show floating alert for in-progress meetings when laptop wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationManager.shared.alertInProgressMeetings(CalendarManager.shared.meetings)
            CalendarManager.shared.fetchMeetings()
        }

        // On first ever launch, show a centered welcome panel so it's
        // visible even if the menu bar icon is hidden behind the notch
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcomePanel()
            }
        }
    }

    // MARK: - Welcome panel

    private func showWelcomePanel() {
        let width: CGFloat = 340
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Welcome to Missting"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: WelcomeView {
            panel.close()
            self.welcomePanel = nil
        })
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        let fittingHeight = hosting.fittingSize.height
        panel.setContentSize(NSSize(width: width, height: fittingHeight))
        panel.contentView = hosting

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        welcomePanel = panel
    }
}

// MARK: - Welcome view

private struct WelcomeView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let img = AppResources.sunflower() {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            Text("Missting is in your menu bar")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Look for the sunflower icon at the top of your screen to view and join meetings.\n\nIf the icon is hidden behind your MacBook's notch, try removing other menu bar icons to make room.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Got it!") { onDismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
    }
}
