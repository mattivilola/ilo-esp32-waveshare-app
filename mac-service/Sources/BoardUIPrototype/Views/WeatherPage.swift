import SwiftUI

struct WeatherPage: View {
    private let hours = [("NOW", "14°"), ("11", "15°"), ("12", "16°"), ("13", "16°"), ("14", "15°")]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Helsinki")
                    .font(.board(20, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Text("SAMPLE DATA")
                    .font(.board(10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(BoardPalette.amber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BoardPalette.amber.opacity(0.11), in: Capsule())
                Spacer()
                Text("Direct Wi-Fi capable")
                    .font(.board(12, weight: .semibold))
                    .foregroundStyle(BoardPalette.signal)
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
                        SectionLabel(title: "Next hours")
                        HStack(spacing: 0) {
                            ForEach(hours, id: \.0) { hour in
                                VStack(spacing: 13) {
                                    Text(hour.0)
                                        .font(.board(11, weight: .bold))
                                        .foregroundStyle(BoardPalette.fog)
                                    Capsule()
                                        .fill(hour.0 == "NOW" ? BoardPalette.cyan : BoardPalette.steel)
                                        .frame(width: 18, height: 5)
                                    Text(hour.1)
                                        .font(.board(18, weight: .semibold))
                                        .foregroundStyle(BoardPalette.mist)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }
                        Text("Rain eases around 13:00")
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
