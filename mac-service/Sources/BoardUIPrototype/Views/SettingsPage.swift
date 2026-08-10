import SwiftUI

struct SettingsPage: View {
    @State private var brightness = 0.72
    @State private var privacyMode = true

    var body: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 13) {
                    SectionLabel(title: "Display")
                    settingHeader("Brightness", value: "72%")
                    DeviceSlider(value: $brightness)
                    Divider().overlay(BoardPalette.steel)
                    settingRow("Idle dim", "2 minutes")
                    settingRow("Screen off", "10 minutes")
                    settingRow("Screensaver", "Pulse clock")
                    Spacer()
                    Text("Dimming the backlight saves power. The LCD itself is not OLED, so the screensaver is primarily ambience and glanceable status.")
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                        .lineSpacing(3)
                }
            }

            VStack(spacing: 14) {
                PulseCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Connections")
                        connectionRow("Wi-Fi", "KNOWN NETWORK", BoardPalette.signal)
                        connectionRow("Mac companion", "PAIRED", BoardPalette.signal)
                        connectionRow("Weather", "DIRECT READY", BoardPalette.cyan)
                        Divider().overlay(BoardPalette.steel)
                        Text("Wi-Fi password changes stay in the secure USB setup flow for now.")
                            .font(.board(11))
                            .foregroundStyle(BoardPalette.fog)
                    }
                }
                PulseCard {
                    HStack(spacing: 15) {
                        Image(nsImage: BrandAsset.image())
                            .resizable()
                            .scaledToFit()
                            .frame(width: 54, height: 54)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Privacy mode")
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
                .frame(height: 105)
            }
        }
        .padding(.vertical, 4)
    }

    private func settingHeader(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.board(15, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
            Spacer()
            Text(value)
                .font(.board(13, weight: .bold))
                .foregroundStyle(BoardPalette.signal)
        }
    }

    private func settingRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(BoardPalette.mist)
            Spacer()
            Text(value).foregroundStyle(BoardPalette.fog)
        }
        .font(.board(13, weight: .semibold))
        .padding(.vertical, 2)
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
}
