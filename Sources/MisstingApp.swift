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

        if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
        } else if UserDefaults.standard.object(forKey: "firstLaunchDate") == nil {
            // Existing install from before firstLaunchDate existed — back-fill it now
            // so the star prompt still fires (7 days out) instead of never at all.
            UserDefaults.standard.set(Date(), forKey: "firstLaunchDate")
        }

        // Show the centered guidance panel on every launch until the user has
        // actually signed in — not just the very first launch ever. Re-running
        // the install script relaunches the app the same way a first install
        // does, so without this, anyone who dismissed the panel (or ran the
        // installer again) without connecting an account gets zero on-screen
        // confirmation that anything happened, with no idea what to do next —
        // especially since the menu bar icon itself can be hidden by the notch.
        if !GoogleAuthManager.shared.isSignedIn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.showWelcomePanel()
            }
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
        let width: CGFloat = 360
        // Borderless, not titled — a native macOS title bar clashes with the
        // dark custom chrome every other panel/popover in the app uses.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Without this, the panel simply never renders at all (not just
        // hidden behind) if the frontmost app is in a fullscreen Space —
        // it's created on the current Space but can't follow into one.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        let width: CGFloat = 360
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 1),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 20) {
                if let img = AppResources.sunflower() {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                Text("Missting is installed!")
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Click the sunflower icon, then **Sign in with Google**.")
                        .foregroundColor(Color(white: 0.75))
                    Text("Icon hidden? Hold ⌘ and drag it next to Wi-Fi or Bluetooth — it'll stay there for good.")
                        .foregroundColor(Color(white: 0.45))
                }
                .font(.system(size: 12.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

                Button("Got it!") { onDismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)

            closeButton(action: onDismiss)
        }
        .frame(width: 360)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private func closeButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "xmark")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color(white: 0.5))
            .frame(width: 22, height: 22)
            .background(Color(white: 0.15))
            .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .padding(12)
}

// MARK: - Star prompt view

private struct StarPromptView: View {
    let onStar: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 18) {
                if let img = AppResources.sunflower() {
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: 48, height: 48)
                }
                Text("Enjoying Missting?")
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Text("It's free and open-source. A star on GitHub helps other people find it.")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(white: 0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Not now") { onDismiss() }
                        .buttonStyle(SecondaryButtonStyle())
                    Button("Star on GitHub") { onStar() }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, 28)
            .padding(.bottom, 28)

            closeButton(action: onDismiss)
        }
        .frame(width: 360)
        .background(Color(white: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
