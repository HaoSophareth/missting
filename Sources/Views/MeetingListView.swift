import SwiftUI
import AVFoundation

struct MeetingListView: View {
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var auth = GoogleAuthManager.shared

    @State private var dismissed: Set<String> = []
    @State private var showChecklist = false
    @State private var showSettings = false
    @State private var isFirstTimeSetup = false
    @State private var signingIn = false
    @State private var signInError: String?
    @State private var dayOffset = 0
    @State private var hasAutoAdvancedDay = false
    @State private var menuBarIconConfirmed = false

    private var accepted: [Meeting] {
        calendar.acceptedMeetings(daysFromToday: dayOffset)
            .filter { !dismissed.contains($0.id) }
    }
    private var pending: [Meeting] {
        calendar.pendingMeetings(daysFromToday: dayOffset)
            .filter { !dismissed.contains($0.id) }
    }

    private var dayLabel: String {
        if dayOffset == 0 { return "Today" }
        let date = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = dayOffset == 1 ? "'Tomorrow'" : "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private struct MeetingGroup { let label: String; let meetings: [Meeting] }

    private var groupedAccepted: [MeetingGroup] {
        let order = ["Morning", "Afternoon", "Evening"]
        var buckets: [String: [Meeting]] = [:]
        for meeting in accepted {
            let hour = Calendar.current.component(.hour, from: meeting.startDate)
            let label: String
            switch hour {
            case 0..<12:  label = "Morning"
            case 12..<17: label = "Afternoon"
            default:      label = "Evening"
            }
            buckets[label, default: []].append(meeting)
        }
        return order.compactMap { key in
            guard let meetings = buckets[key], !meetings.isEmpty else { return nil }
            return MeetingGroup(label: key, meetings: meetings)
        }
    }

    var body: some View {
        Group {
            if showChecklist {
                checklistPanel
            } else if showSettings {
                settingsPanel
            } else {
                mainPanel
            }
        }
        // fixedSize on the outermost view so it constrains the dark background too,
        // giving NSHostingController an accurate ideal size to report.
        .fixedSize(horizontal: true, vertical: true)
        .background(Color(white: 0.06))
        .onAppear {
            dismissed.removeAll()
            CalendarManager.shared.startRefreshingIfSignedIn()
        }
        .onChange(of: auth.isSignedIn) { signedIn in
            if signedIn {
                CalendarManager.shared.startRefreshingIfSignedIn()
                // Most people never think to open Settings on their own, so
                // the first time anyone connects an account, walk them there
                // directly instead of leaving Calendars/Minerva/timing
                // buried behind a small gear icon they may never notice.
                if !UserDefaults.standard.bool(forKey: "hasShownInitialSetup") {
                    UserDefaults.standard.set(true, forKey: "hasShownInitialSetup")
                    isFirstTimeSetup = true
                    showChecklist = true
                }
            }
        }
        .onChange(of: calendar.meetings) { meetings in
            NotificationManager.shared.checkAndNotify(meetings: meetings, offsets: settings.enabledOffsets)
            advanceToFirstMeetingDayIfNeeded()
        }
    }

    /// Runs once per session, right after the first real fetch lands: if
    /// today has nothing, jump straight to the next day that actually has a
    /// meeting instead of leaving a first-time (or simply schedule-free)
    /// user staring at an empty "No meetings" today with no obvious next step.
    private func advanceToFirstMeetingDayIfNeeded() {
        guard !hasAutoAdvancedDay, dayOffset == 0 else { return }
        hasAutoAdvancedDay = true
        guard calendar.acceptedMeetings(daysFromToday: 0).isEmpty,
              calendar.pendingMeetings(daysFromToday: 0).isEmpty else { return }
        for offset in 1...6 {
            if !calendar.acceptedMeetings(daysFromToday: offset).isEmpty
                || !calendar.pendingMeetings(daysFromToday: offset).isEmpty {
                dayOffset = offset
                return
            }
        }
    }

    // MARK: - Panels

    private var checklistPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Before you start")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            checklistRow(done: true, title: "Google Calendar", subtitle: "Connected")

            Divider().background(Color(white: 0.12)).padding(.horizontal, 16)

            // Whether the icon actually got dragged isn't something we can
            // detect, so this is a manual, tappable confirmation rather than
            // an automatic status — same pattern as any real checklist.
            checklistRow(
                done: menuBarIconConfirmed,
                title: "Menu bar icon",
                subtitle: "Hold ⌘ and drag it just left of Control Center so it never gets hidden.",
                onToggle: { menuBarIconConfirmed.toggle() },
                showDragHint: true
            )
            .padding(.bottom, 16)
        }
        .frame(width: 300)
        // No manual "Continue" — once every item is checked, there's nothing
        // left to decide, so move straight into Settings on its own.
        .onChange(of: menuBarIconConfirmed) { confirmed in
            guard confirmed else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showChecklist = false
                    showSettings = true
                }
            }
        }
    }

    private func checklistRow(
        done: Bool,
        title: String,
        subtitle: String,
        onToggle: (() -> Void)? = nil,
        showDragHint: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if let onToggle {
                    Button(action: onToggle) { checklistIcon(done: done) }
                        .buttonStyle(.plain)
                } else {
                    checklistIcon(done: done)
                }
            }
            .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                if showDragHint {
                    DragHintView()
                        .padding(.top, 4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func checklistIcon(done: Bool) -> some View {
        Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 15))
            .foregroundColor(done ? Color(red: 0.2, green: 0.78, blue: 0.42) : Color(white: 0.3))
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isFirstTimeSetup ? "Quick setup" : "Settings")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSettings = false
                        isFirstTimeSetup = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(white: 0.5))
                        .frame(width: 24, height: 24)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, isFirstTimeSetup ? 4 : 8)

            if isFirstTimeSetup {
                Text("You're connected — set your preferences below.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            }

            Divider().background(Color(white: 0.12))
            SettingsView()
        }
        .frame(width: 320)
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            header
            if auth.isSignedIn { dayPicker }
            ScrollView {
                VStack(spacing: 8) {
                    if !auth.isSignedIn {
                        authPrompt
                    } else if accepted.isEmpty && pending.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedAccepted, id: \.label) { group in
                            Text(group.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color(white: 0.3))

                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, group.label == groupedAccepted.first?.label ? 0 : 4)
                            ForEach(group.meetings) { meeting in
                                MeetingCardView(meeting: meeting) {
                                    dismissed.insert(meeting.id)
                                }
                            }
                        }
                        if !pending.isEmpty {
                            Text("Pending invites")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Color(white: 0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                            ForEach(pending) { meeting in
                                PendingMeetingCard(meeting: meeting) {
                                    dismissed.insert(meeting.id)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 460)
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Missting")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
            Spacer()
            if auth.isSignedIn {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSettings = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13))
                        .foregroundColor(showSettings
                            ? Color(red: 0.31, green: 0.56, blue: 0.97)
                            : Color(white: 0.5))
                }
                .buttonStyle(.plain)
                Button {
                    CalendarManager.shared.fetchMeetings()
                } label: {
                    Text("Refresh")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.53))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Capsule().stroke(Color(white: 0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private var dayPicker: some View {
        HStack(spacing: 0) {
            Button {
                dayOffset = max(0, dayOffset - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dayOffset > 0 ? Color(white: 0.7) : Color(white: 0.2))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayOffset == 0)

            Spacer()

            Text(dayLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(white: 0.5))

            Spacer()

            Button {
                dayOffset = min(6, dayOffset + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dayOffset < 6 ? Color(white: 0.7) : Color(white: 0.2))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayOffset == 6)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
    }

    private var footer: some View {
        HStack {
            if auth.isSignedIn {
                Text("Updates every minute")
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.27))
                Spacer()
                Button("Sign out") {
                    GoogleAuthManager.shared.signOut()
                    CalendarManager.shared.meetings = []
                }
                .font(.system(size: 10))
                .foregroundColor(Color(white: 0.27))
                .buttonStyle(.plain)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No meetings")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.33))
        }
        .padding(.vertical, 28)
    }

    private var authPrompt: some View {
        VStack(spacing: 12) {
            if let img = AppResources.sunflower() {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .padding(.bottom, 4)
            }
            Text("Welcome to Missting")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Text("Sign in with Google to see your upcoming meetings and get notified before they start.")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.4))
                .multilineTextAlignment(.center)
            if let err = signInError {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(Color(red: 1, green: 0.4, blue: 0.4))
            }
            Button {
                signingIn = true
                signInError = nil
                // Close our own popover so it doesn't sit stacked behind the
                // system Google sign-in window while the user authenticates.
                MenuBarManager.shared.closePopover()
                Task {
                    do {
                        try await GoogleAuthManager.shared.signIn()
                    } catch {
                        await MainActor.run { signInError = "Sign-in failed. Try again." }
                    }
                    await MainActor.run {
                        signingIn = false
                        MenuBarManager.shared.showPopover()
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if signingIn { ProgressView().scaleEffect(0.7).tint(.white) }
                    Text(signingIn ? "Signing in…" : "Sign in with Google")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(signingIn)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
    }
}

/// Plays the real screen-recorded loop of dragging the icon across the
/// actual menu bar.
private struct DragHintView: View {
    private let width: CGFloat = 236
    private let aspectRatio: CGFloat = 334.0 / 40.0 // native video dimensions

    var body: some View {
        VideoLoopView(url: AppResources.menuBarDragVideo())
            // Aspect-fit, uncropped, no distortion — the whole recording
            // stays visible at every point in the loop.
            .frame(width: width, height: width / aspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct VideoLoopView: NSViewRepresentable {
    let url: URL?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        if let url { context.coordinator.start(url: url, in: view) }
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}

    final class Coordinator {
        private var player: AVPlayer?
        private var endObserver: NSObjectProtocol?

        func start(url: URL, in view: PlayerLayerView) {
            let player = AVPlayer(url: url)
            player.isMuted = true
            player.actionAtItemEnd = .none
            view.playerLayer.player = player
            view.playerLayer.videoGravity = .resizeAspect
            self.player = player
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player.currentItem,
                queue: .main
            ) { _ in
                player.seek(to: .zero)
                player.play()
            }
            player.play()
        }

        deinit {
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        }
    }
}

private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
    }
}
