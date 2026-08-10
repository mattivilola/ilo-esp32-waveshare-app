import SwiftUI

struct SettingsPage: View {
    let xNewsEnabled: Bool
    @State private var screensaverMinutes = 2
    @State private var displayOffMinutes = 10
    @State private var privacyMode = false
    @State private var uses24HourClock = true
    @State private var usesFahrenheit = false
    @State private var focusMinutes = 25

    var body: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 13) {
                    SectionLabel(title: "Display")
                    settingButton("Pulse screensaver", value: minutes(screensaverMinutes)) {
                        screensaverMinutes = next(screensaverMinutes, in: [0, 2, 5])
                    }
                    settingButton("Display off", value: minutes(displayOffMinutes)) {
                        displayOffMinutes = next(displayOffMinutes, in: [0, 5, 10, 30])
                    }
                    settingButton("Turn display off now", value: "SLEEP") {}
                    Spacer()
                    Text("This exact 5B board exposes binary backlight on/off, not PWM brightness. The first wake touch is consumed so it cannot activate a hidden control.")
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 14) {
                PulseCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(title: "Pulse & units")
                        compactSettingButton("Clock", value: uses24HourClock ? "24 HOUR" : "12 HOUR") {
                            uses24HourClock.toggle()
                        }
                        compactSettingButton("Temperature", value: usesFahrenheit ? "FAHRENHEIT" : "CELSIUS") {
                            usesFahrenheit.toggle()
                        }
                        compactSettingButton("Focus session", value: "\(focusMinutes) MIN") {
                            focusMinutes = next(focusMinutes, in: [25, 45, 60])
                        }
                    }
                }
                .frame(height: 160)
                PulseCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Connections")
                        connectionRow("Wi-Fi", "KNOWN NETWORK", BoardPalette.signal)
                        connectionRow("Mac companion", "PAIRED", BoardPalette.signal)
                        connectionRow("Weather", "DIRECT READY", BoardPalette.cyan)
                        connectionRow(
                            "X News",
                            xNewsEnabled ? "MAC ENABLED" : "MAC DISABLED",
                            xNewsEnabled ? BoardPalette.signal : BoardPalette.fog
                        )
                    }
                }
                .frame(height: 160)
                PulseCard {
                    HStack(spacing: 15) {
                        Image(nsImage: BrandAsset.image())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Task summaries")
                                .font(.board(15, weight: .semibold))
                                .foregroundStyle(BoardPalette.mist)
                            Text("Hide task summaries on the board")
                                .font(.board(11))
                                .foregroundStyle(BoardPalette.fog)
                        }
                        Spacer()
                        DeviceToggle(isOn: $privacyMode)
                    }
                }
                .frame(height: 95)
            }
        }
        .padding(.vertical, 4)
    }

    private func compactSettingButton(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .foregroundStyle(BoardPalette.signal)
            }
            .font(.board(11, weight: .semibold))
            .foregroundStyle(BoardPalette.mist)
            .padding(.horizontal, 11)
            .frame(height: 31)
            .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func settingButton(_ title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.board(13, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Spacer()
                Text(value)
                    .font(.board(12, weight: .bold))
                    .foregroundStyle(BoardPalette.signal)
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func connectionRow(_ title: String, _ value: String, _ tint: Color) -> some View {
        HStack {
            StatusDot(color: tint)
            Text(title)
                .font(.board(13, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
            Spacer()
            Text(value)
                .font(.board(10, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(tint)
        }
        .padding(.vertical, 2)
    }

    private func minutes(_ value: Int) -> String {
        value == 0 ? "Never" : "\(value) min"
    }

    private func next(_ value: Int, in choices: [Int]) -> Int {
        guard let index = choices.firstIndex(of: value) else { return choices[0] }
        return choices[(index + 1) % choices.count]
    }
}
