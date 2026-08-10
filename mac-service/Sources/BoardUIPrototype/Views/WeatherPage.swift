import SwiftUI

struct WeatherPage: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Helsinki")
                    .font(.board(20, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Text("PREVIEW DATA")
                    .font(.board(10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(BoardPalette.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BoardPalette.amber.opacity(0.11), in: Capsule())
                Spacer()
                Text("Weather data by Open-Meteo.com")
                    .font(.board(12, weight: .semibold))
                    .foregroundStyle(BoardPalette.fog)
            }
            HStack(spacing: 16) {
                PulseCard {
                    VStack(alignment: .leading, spacing: 5) {
                        SectionLabel(title: "Now")
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("14")
                                .font(.board(82, weight: .bold))
                                .foregroundStyle(BoardPalette.mist)
                            Text("°C")
                                .font(.board(24, weight: .semibold))
                                .foregroundStyle(BoardPalette.fog)
                        }
                        Text("Light rain")
                            .font(.board(18, weight: .semibold))
                            .foregroundStyle(BoardPalette.cyan)
                        Spacer()
                        Text("Feels 12°  ·  Wind 5 m/s")
                            .font(.board(12))
                            .foregroundStyle(BoardPalette.fog)
                    }
                }
                .frame(width: 350, height: 235)

                PulseCard {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: "Independent weather")
                        VStack(alignment: .leading, spacing: 12) {
                            architectureRow("HTTPS", "CERTIFICATE VERIFIED")
                            architectureRow("Clock", "SYNC BEFORE REQUEST")
                            architectureRow("Refresh", "EVERY 30 MIN")
                        }
                        Spacer()
                        Text("Cached values are visibly marked STALE")
                            .font(.board(13, weight: .semibold))
                            .foregroundStyle(BoardPalette.cyan)
                    }
                }
                .frame(height: 235)
            }
            HStack(spacing: 12) {
                forecast("TODAY", "16° / 10°", "Rain", BoardPalette.cyan)
                forecast("TUE", "18° / 11°", "Cloudy", BoardPalette.fog)
                forecast("WED", "20° / 12°", "Clear", BoardPalette.signal)
            }
            .frame(height: 100)
        }
        .padding(.vertical, 4)
    }

    private func architectureRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.board(13, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
            Spacer()
            Text(value)
                .font(.board(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(BoardPalette.signal)
        }
    }

    private func forecast(_ day: String, _ temperature: String, _ condition: String, _ tint: Color) -> some View {
        HStack {
            StatusDot(color: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(day)
                    .font(.board(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(BoardPalette.fog)
                Text(condition)
                    .font(.board(14, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
            }
            Spacer()
            Text(temperature)
                .font(.board(16, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
