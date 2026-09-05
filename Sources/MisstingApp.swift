import AppKit
import SwiftUI
import ServiceManagement
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var welcomePanel: NSPanel?
    private var starPanel: NSPanel?

    private static let starRepoURL = URL(string: "https://github.com/HaoSophareth/missting")!

    /// Sparkle auto-updater — checks the appcast feed on a schedule and
    /// installs signed updates from GitHub Releases.
    let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if #available(macOS 13.0, *) { try? SMAppService.mainApp.register() }
        MenuBarManager.shared.setup()
        CalendarManager.shared.startRefreshingIfSignedIn()
        _ = CallDetector.shared

        // Show floating alert for in-progress meetings when laptop wakes from sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NotificationManager.shared.alertInProgressMeetings(CalendarManager.shared.meetings)
            CalendarManager.shared.fetchMeetings()
            AutoJoinManager.shared.checkInProgressMeetings()
        }

        // On first ever launch, show a centered welcome panel so it's
        // visible even if the menu bar icon is hidden behind the notch
        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcomePanel()
            }
        } else if UserDefaults.standard.object(forKey: "firstLaunchDate") == nil {
            // Existing install from before firstLaunchDate existed — back-fill it now
            // so the star prompt still fires (7 days out) instead of never at all.
            UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
        }

        maybeShowStarPrompt()
    }

    // MARK: - Star prompt

    /// One week after first launch, ask once for a GitHub star. Never repeats.
    private func maybeShowStarPrompt() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "hasShownStarPrompt"),
              let firstLaunch = d.object(forKey: "firstLaunchDate") as? Date,
              Date().timeIntervalSince(firstLaunch) >= 7 * 24 * 60 * 60
        else { return }

        d.set(true, forKey: "hasShownStarPrompt")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.showStarPanel()
        }
    }

    private func showStarPanel() {
        let width: CGFloat = 340
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Enjoying Missting?"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let hosting = NSHostingView(rootView: StarPromptView(
            onStar: { [weak self] in
                NSWorkspace.shared.open(AppDelegate.starRepoURL)
                panel.close()
                self?.starPanel = nil
            },
            onDismiss: { [weak self] in
                panel.close()
                self?.starPanel = nil
            }
        ))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        let fittingHeight = hosting.fittingSize.height
        panel.setContentSize(NSSize(width: width, height: fittingHeight))
        panel.contentView = hosting

        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        starPanel = panel
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
        panel.appearance = NSAppearance(named: .darkAqua)

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
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Look for the sunflower icon at the top of your screen to view and join meetings.\n\nIf it's hidden behind your MacBook's notch (common with lots of menu bar apps open), hold ⌘ and drag it next to icons like Wi-Fi or Bluetooth — once you drop it there, it stays put for good.")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
            Button("Got it!") { onDismiss() }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
        .background(Color(white: 0.06))
    }
}

// MARK: - Star prompt view

private struct StarPromptView: View {
    let onStar: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            if let img = AppResources.sunflower() {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 56, height: 56)
            }
            Text("Enjoying Missting?")
                .font(.headline)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("It's free and open-source. A star on GitHub helps other people find it.")
                .font(.subheadline)
                .foregroundColor(Color(white: 0.5))
                .multilineTextAlignment(.center)
            HStack(spacing: 10) {
                Button("Not now") { onDismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Star on GitHub") { onStar() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 340)
        .background(Color(white: 0.06))
    }
}
