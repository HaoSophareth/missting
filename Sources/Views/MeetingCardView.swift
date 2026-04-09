import SwiftUI
import AppKit

struct MeetingCardView: View {
    let meeting: Meeting
    let onDismiss: () -> Void

    @EnvironmentObject private var autoJoin: AutoJoinManager
    @State private var tick = 0
    @State private var joinedLocally = false

    private var isScheduled: Bool { autoJoin.isScheduled(meeting.id) }
    private var mins: Int { meeting.minsUntilStart }
    private var hasLink: Bool { meeting.joinURL != nil }
    private var hasJoined: Bool { joinedLocally || JoinTracker.shared.hasJoined(meeting.id) }
    private var minsUntilJoin: Int {
        let offset = SettingsManager.shared.autoJoinOffset
        let joinDate = meeting.startDate.addingTimeInterval(-Double(offset) * 60)
        return Int((joinDate.timeIntervalSinceNow / 60).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: status + dismiss
            HStack(alignment: .center, spacing: 0) {
                statusLabel
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.35))
                        .frame(width: 18, height: 18)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Title + time
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(meeting.isMissed ? Color(white: 0.3) : Color(white: 0.4))
                Text(meeting.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(meeting.isMissed ? Color(white: 0.4) : .white)
                    .lineLimit(1)
                if !hasLink {
                    Text("· No link")
                        .font(.system(size: 11))
                        .foregroundColor(Color(white: 0.3))
                }
            }

            // Action buttons — not shown for missed meetings
            if !meeting.isMissed && (hasLink || isScheduled) {
                HStack(spacing: 6) {
                    if meeting.isInProgress {
                        // Once live, hide Auto-join/Scheduled/Cancel — only show join state
                        if hasLink {
                            if hasJoined {
                                Button("Joined") { NSWorkspace.shared.open(meeting.joinURL!) }
                                    .buttonStyle(JoinedButtonStyle())
                            } else {
                                Button("Already in it") {
                                    JoinTracker.shared.markJoined(meeting.id)
                                    joinedLocally = true
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                Button("Join now") {
                                    JoinTracker.shared.markJoined(meeting.id)
                                    joinedLocally = true
                                    NSWorkspace.shared.open(meeting.joinURL!)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                            }
                        }
                    } else {
                        if hasLink && !isScheduled {
                            Button("Auto-join") { autoJoin.schedule(meeting) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if isScheduled {
                            Text("Scheduled")
                                .font(.system(size: 11))
                                .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .overlay(Capsule().stroke(Color(red: 0.96, green: 0.65, blue: 0.14), lineWidth: 0.5))
                            Button("Cancel") { autoJoin.cancelManually(meeting.id) }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        if hasLink {
                            Button("Join now") {
                                if isScheduled { autoJoin.cancel(meeting.id) }
                                JoinTracker.shared.markJoined(meeting.id)
                                joinedLocally = true
                                NSWorkspace.shared.open(meeting.joinURL!)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(cardBorder, lineWidth: 0.5)
        )
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            tick += 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingAutoJoined)) { note in
            if let id = note.object as? String, id == meeting.id {
                joinedLocally = true
            }
        }
    }

    // MARK: - Helpers

    private var cardBackground: Color {
        if meeting.isMissed     { return Color(white: 0.07) }
        if meeting.isInProgress {
            return hasJoined
                ? Color(red: 0.07, green: 0.15, blue: 0.09)
                : Color(red: 0.17, green: 0.1, blue: 0.1)
        }
        return Color(white: 0.1)
    }

    private var cardBorder: Color {
        if meeting.isMissed     { return Color(white: 0.1) }
        if meeting.isInProgress {
            return hasJoined
                ? Color(red: 0.2, green: 0.78, blue: 0.42).opacity(0.25)
                : Color(red: 1.0, green: 0.35, blue: 0.35).opacity(0.25)
        }
        return Color(white: 0.14)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if meeting.isMissed {
            Text("Missed")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(white: 0.35))
        } else if meeting.isInProgress {
            HStack(spacing: 4) {
                Circle()
                    .fill(hasJoined ? Color(red: 0.2, green: 0.78, blue: 0.42) : Color(red: 1.0, green: 0.35, blue: 0.35))
                    .frame(width: 5, height: 5)
                Text("In progress · \(meeting.minsElapsed)m in · \(meeting.minsRemaining)m left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(hasJoined ? Color(red: 0.2, green: 0.78, blue: 0.42) : Color(red: 1.0, green: 0.45, blue: 0.45))
            }
        } else if isScheduled {
            Text("Auto-joining in \(formatMins(max(minsUntilJoin, 0)))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
        } else {
            Text(mins <= 1 ? "Starting now" : "In \(formatMins(mins))")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Color(red: 0.655, green: 0.545, blue: 0.98))
        }
    }

    private var timeLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: meeting.startDate)
    }

    private func formatMins(_ m: Int) -> String {
        guard m >= 60 else { return "~\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "~\(h)h" : "~\(h)h \(rem)m"
    }
}

// MARK: - Pending invite card

struct PendingMeetingCard: View {
    @EnvironmentObject private var autoJoin: AutoJoinManager
    let meeting: Meeting
    let onDismiss: () -> Void

    private var timeLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return fmt.string(from: meeting.startDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Pending invite")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.96, green: 0.75, blue: 0.3))
                Spacer()
                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.35))
                        .frame(width: 18, height: 18)
                        .background(Color(white: 0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Text(timeLabel)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(Color(white: 0.4))
                Text(meeting.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(white: 0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Button("Accept") { CalendarManager.shared.rsvp(meeting: meeting, accept: true) }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Decline") { CalendarManager.shared.rsvp(meeting: meeting, accept: false) }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(red: 0.12, green: 0.1, blue: 0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(Color(red: 0.96, green: 0.75, blue: 0.3).opacity(0.2), lineWidth: 0.5))
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Color(red: 0.31, green: 0.56, blue: 0.97))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.75))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(Capsule().stroke(Color(white: 0.25), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct JoinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Color(red: 0.2, green: 0.78, blue: 0.42))
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(Color(red: 0.2, green: 0.78, blue: 0.42).opacity(0.12))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DismissButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.33))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .overlay(Capsule().stroke(Color(white: 0.17), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
