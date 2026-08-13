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
            PulseCard {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Now")
                        HStack(spacing: 20) {
                            weatherGlyph("cloud.rain.fill", size: 92, tint: BoardPalette.cyan)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("14")
                                        .font(.board(54, weight: .bold))
                                        .foregroundStyle(BoardPalette.mist)
                                    Text("°C")
                                        .font(.board(20, weight: .semibold))
                                        .foregroundStyle(BoardPalette.fog)
                                }
                                Text("Light rain")
                                    .font(.board(18, weight: .semibold))
                                    .foregroundStyle(BoardPalette.cyan)
                                Text("Current conditions in Helsinki")
                                    .font(.board(12))
                                    .foregroundStyle(BoardPalette.fog)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .overlay(BoardPalette.steel)
                        .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 17) {
                        SectionLabel(title: "Today at a glance")
                        HStack(spacing: 34) {
                            weatherStat("Feels like", "12°C")
                            weatherStat("Wind", "5.0 m/s")
                            weatherStat("High / low", "16° / 10°")
                        }
                        Text("Tomorrow: Cloudy, 18° / 11°")
                            .font(.board(13, weight: .semibold))
                            .foregroundStyle(BoardPalette.cyan)
                    }
                    .frame(width: 430, alignment: .leading)
                }
            }
            .frame(height: 216)

            HStack(spacing: 12) {
                forecast("TODAY", "16° / 10°", "Rain", "cloud.rain.fill", BoardPalette.cyan)
                forecast("TOMORROW", "18° / 11°", "Cloudy", "cloud.fill", BoardPalette.fog)
                forecast("+2 DAYS", "20° / 12°", "Clear", "sun.max.fill", BoardPalette.amber)
            }
            .frame(height: 110)
        }
        .padding(.vertical, 4)
    }

    private func weatherGlyph(_ symbol: String, size: CGFloat, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.4, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(tint, BoardPalette.mist)
            .frame(width: size, height: size)
            .background(BoardPalette.raised, in: RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }

    private func weatherStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased())
                .font(.board(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(BoardPalette.fog)
            Text(value)
                .font(.board(17, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
        }
    }

    private func forecast(
        _ day: String,
        _ temperature: String,
        _ condition: String,
        _ symbol: String,
        _ tint: Color
    ) -> some View {
        HStack(spacing: 15) {
            weatherGlyph(symbol, size: 58, tint: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(day)
                    .font(.board(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(BoardPalette.fog)
                Text(condition)
                    .font(.board(14, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Text(temperature)
                    .font(.board(13, weight: .semibold))
                    .foregroundStyle(BoardPalette.cyan)
            }
            Spacer()
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
