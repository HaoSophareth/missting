import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsManager
    @EnvironmentObject private var calendar: CalendarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: - Notifications
            HStack {
                Text("Notify before meetings")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                MinuteField(value: $settings.notificationOffset)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color(white: 0.12))

            // MARK: - Auto-join timing
            HStack {
                Text("Auto-join before start")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
                MinuteField(value: $settings.autoJoinOffset)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(Color(white: 0.12))

            // MARK: - All events
            Button {
                settings.showAllEvents.toggle()
                CalendarManager.shared.fetchMeetings()
            } label: {
                HStack(spacing: 10) {
                    Text("Show all events")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: settings.showAllEvents ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(settings.showAllEvents
                            ? Color(red: 0.31, green: 0.56, blue: 0.97)
                            : Color(white: 0.25))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
        .simultaneousGesture(TapGesture().onEnded {
            NSApp.keyWindow?.makeFirstResponder(nil)
        })
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

}

private struct MinuteField: View {
    @Binding var value: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Button { value = max(0, value - 1); text = "\(value)" } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 22, height: 22)
                    .background(Color(white: 0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 2) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 28)
                    .focused($focused)
                    .onAppear { text = "\(value)" }
                    .onSubmit {
                        if let v = Int(text), v >= 0 { value = v } else { text = "\(value)" }
                        focused = false
                    }
                    .onChange(of: text) { v in
                        let digits = v.filter(\.isNumber)
                        if digits != v { text = digits }
                        if let v = Int(digits) { value = v }
                    }
                    .onChange(of: focused) { isFocused in
                        if !isFocused {
                            if let v = Int(text), v >= 0 { value = v } else { text = "\(value)" }
                        }
                    }
                Text("m")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.45))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color(white: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Button { value += 1; text = "\(value)" } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(white: 0.6))
                    .frame(width: 22, height: 22)
                    .background(Color(white: 0.18))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }
}
