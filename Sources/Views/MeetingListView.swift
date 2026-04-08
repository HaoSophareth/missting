import SwiftUI

struct MeetingListView: View {
    @EnvironmentObject private var calendar: CalendarManager
    @EnvironmentObject private var settings: SettingsManager
    @ObservedObject private var auth = GoogleAuthManager.shared

    @State private var dismissed: Set<String> = []
    @State private var showSettings = false
    @State private var signingIn = false
    @State private var signInError: String?
    @State private var dayOffset = 0

    private var accepted: [Meeting] {
        calendar.acceptedMeetings(daysFromToday: dayOffset)
            .filter { !dismissed.contains($0.id) }
    }
    private var pending: [Meeting] {
        calendar.pendingMeetings(daysFromToday: dayOffset)
            .filter { !dismissed.contains($0.id) }
    }

    private var dayLabel: String { dayOffset == 0 ? "Today" : "Tomorrow" }

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
            if showSettings {
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
            if signedIn { CalendarManager.shared.startRefreshingIfSignedIn() }
        }
        .onChange(of: calendar.meetings) { meetings in
            NotificationManager.shared.checkAndNotify(meetings: meetings, offsets: settings.enabledOffsets)
        }
    }

    // MARK: - Panels

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSettings = false }
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
            .padding(.bottom, 8)

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
                dayOffset = min(1, dayOffset + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(dayOffset < 1 ? Color(white: 0.7) : Color(white: 0.2))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(dayOffset == 1)
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
            Text(dayOffset == 0 ? "No meetings today" : "No meetings tomorrow")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.33))
        }
        .padding(.vertical, 28)
    }

    private var authPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 32))
                .foregroundColor(Color(white: 0.3))
                .padding(.bottom, 4)
            Text("Connect Google Calendar")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(white: 0.7))
            Text("Sign in to see your upcoming meetings and get notified before they start.")
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
                Task {
                    do {
                        try await GoogleAuthManager.shared.signIn()
                    } catch {
                        await MainActor.run { signInError = "Sign-in failed. Try again." }
                    }
                    await MainActor.run { signingIn = false }
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
