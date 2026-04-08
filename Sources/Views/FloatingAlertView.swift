import SwiftUI
import AppKit

struct FloatingAlertView: View {
    let meeting: Meeting
    let onJoin: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var autoJoin: AutoJoinManager
    @State private var tick = 0
    @State private var joinedLocally = false

    private var isScheduled: Bool { autoJoin.isScheduled(meeting.id) }
    private var mins: Int { meeting.minsUntilStart }
    private var hasJoined: Bool { joinedLocally || JoinTracker.shared.hasJoined(meeting.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status row
            HStack(spacing: 0) {
                if isScheduled {
                    Text("Auto-joining in ~\(max(mins, 0)) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                } else if meeting.isInProgress {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.35, blue: 0.35))
                            .frame(width: 6, height: 6)
                        Text("In progress · \(meeting.minsRemaining)m left")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(red: 1.0, green: 0.45, blue: 0.45))
                    }
                } else {
                    Text(mins <= 1 ? "Starting now" : "In ~\(mins) min")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(red: 0.655, green: 0.545, blue: 0.98))
                }

                Spacer()

                if meeting.joinURL != nil {
                    if meeting.isInProgress && hasJoined {
                        Button("Joined") { onJoin() }
                            .buttonStyle(FloatJoinedStyle())
                    } else {
                        Button("Join now") {
                            if isScheduled { autoJoin.cancel(meeting.id) }
                            JoinTracker.shared.markJoined(meeting.id)
                            NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
                            joinedLocally = true
                            onJoin()
                        }
                        .buttonStyle(FloatPrimaryStyle())
                    }
                }

                Button { onDismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(white: 0.4))
                        .frame(width: 18, height: 18)
                        .background(Color(white: 0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().background(Color(white: 0.2))

            // Meeting row
            HStack(spacing: 8) {
                Text(timeLabel)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(Color(white: 0.45))
                Text(meeting.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                if meeting.isInProgress {
                    if meeting.joinURL != nil && !hasJoined {
                        Button("Already in it") {
                            JoinTracker.shared.markJoined(meeting.id)
                            NotificationCenter.default.post(name: .meetingAutoJoined, object: meeting.id)
                            onDismiss()
                        }
                        .buttonStyle(FloatSecondaryStyle())
                    }
                } else {
                    if meeting.joinURL != nil && !isScheduled {
                        Button("Auto-join") { autoJoin.schedule(meeting) }
                            .buttonStyle(FloatSecondaryStyle())
                    }
                    if isScheduled {
                        Button("Cancel") { autoJoin.cancel(meeting.id) }
                            .buttonStyle(FloatSecondaryStyle())
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(white: 0.13))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .padding(4)
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in tick += 1 }
        .onReceive(NotificationCenter.default.publisher(for: .meetingAutoJoined)) { note in
            if let id = note.object as? String, id == meeting.id { joinedLocally = true }
        }
    }

    private var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: meeting.startDate)
    }
}

// MARK: - Button styles

struct FloatPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(red: 0.31, green: 0.56, blue: 0.97))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FloatJoinedStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(white: 0.35))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct FloatSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.5))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().stroke(Color(white: 0.25), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
