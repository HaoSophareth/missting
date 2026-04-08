import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var calendar: CalendarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Notifications
            Text("Notify me before meetings")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                alertChip("30m", isOn: $settings.alert30)
                alertChip("15m", isOn: $settings.alert15)
                alertChip("10m", isOn: $settings.alert10)
                alertChip("5m",  isOn: $settings.alert5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Divider().background(Color(white: 0.12))

            // MARK: - Auto-join timing
            Text("Auto-join before start")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            HStack(spacing: 8) {
                autoJoinChip("0m", value: 0)
                autoJoinChip("1m", value: 1)
                autoJoinChip("2m", value: 2)
                autoJoinChip("5m", value: 5)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Divider().background(Color(white: 0.12))

            // MARK: - Calendars
            Text("Calendars")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            if calendar.availableCalendars.isEmpty {
                Text("Calendars will appear here after sign-in")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.35))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(calendar.availableCalendars) { cal in
                        let isEnabled = !settings.disabledCalendarIds.contains(cal.id)
                        Button {
                            if isEnabled {
                                settings.disabledCalendarIds.insert(cal.id)
                            } else {
                                settings.disabledCalendarIds.remove(cal.id)
                            }
                            CalendarManager.shared.fetchMeetings()
                        } label: {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(colorFromHex(cal.colorHex) ?? Color(white: 0.4))
                                    .frame(width: 9, height: 9)
                                Text(cal.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(isEnabled ? Color(white: 0.85) : Color(white: 0.35))
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(isEnabled ? Color(red: 0.31, green: 0.56, blue: 0.97) : Color(white: 0.25))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }

            Divider().background(Color(white: 0.12))

            // MARK: - Minerva Calendar
            HStack(spacing: 8) {
                Text("Minerva class calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(calendar.minervaCalendarConnected
                              ? Color(red: 0.2, green: 0.78, blue: 0.42)
                              : Color(red: 0.9, green: 0.3, blue: 0.3))
                        .frame(width: 7, height: 7)
                    Text(calendar.minervaCalendarConnected ? "Connected" : "Not connected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(calendar.minervaCalendarConnected
                                         ? Color(red: 0.2, green: 0.78, blue: 0.42)
                                         : Color(red: 0.9, green: 0.3, blue: 0.3))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 14) {
                Text("Missting auto-detects your class join links from your Minerva Academic calendar. Follow these steps to connect it:")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.4))
                    .fixedSize(horizontal: false, vertical: true)

                setupStep(
                    number: "1",
                    text: "On **Forum**, open your profile menu → **Edit Profile** → scroll to the bottom → click **Copy Calendar Link**"
                )
                setupStep(
                    number: "2",
                    text: "Open **Google Calendar** → click **+** next to \"Other calendars\" → **From URL** → paste the link → **Add calendar**"
                )
                setupStep(
                    number: "3",
                    text: "Return here and refresh — the status above will turn **green** once your classes are detected"
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 300)
    }

    // MARK: - Helpers

    private func colorFromHex(_ hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
        return Color(
            red:   Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8)  & 0xFF) / 255,
            blue:  Double(val         & 0xFF) / 255
        )
    }

    // MARK: - Step row

    private func setupStep(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color(red: 0.31, green: 0.56, blue: 0.97))
                .frame(width: 18, height: 18)
                .background(Color(red: 0.31, green: 0.56, blue: 0.97).opacity(0.15))
                .clipShape(Circle())

            Group {
                if let attr = try? AttributedString(
                    markdown: text,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attr)
                } else {
                    Text(text)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(Color(white: 0.5))
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Auto-join chip

    private func autoJoinChip(_ label: String, value: Int) -> some View {
        let selected = settings.autoJoinOffset == value
        return Button { settings.autoJoinOffset = value } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(selected ? .white : Color(white: 0.5))
                .frame(width: 52, height: 36)
                .background(selected
                    ? Color(red: 0.31, green: 0.56, blue: 0.97)
                    : Color(white: 0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alert chip

    private func alertChip(_ label: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isOn.wrappedValue ? .white : Color(white: 0.5))
                .frame(width: 52, height: 36)
                .background(isOn.wrappedValue
                    ? Color(red: 0.31, green: 0.56, blue: 0.97)
                    : Color(white: 0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
