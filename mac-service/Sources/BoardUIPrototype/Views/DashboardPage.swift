import SwiftUI

struct DashboardPage: View {
    var body: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(title: "Attention")
                    Text("1")
                        .font(.board(78, weight: .bold))
                        .foregroundStyle(BoardPalette.amber)
                        .padding(.top, 10)
                    Text("Codex needs review")
                        .font(.board(18, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text("One plan is waiting on your Mac")
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.fog)
                        .padding(.top, 6)
                    Spacer()
                    Text("READ ONLY")
                        .font(.board(11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(BoardPalette.signal)
                    Text("Review actions remain on Mac")
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                        .padding(.top, 4)
                }
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Active work")
                        .font(.board(20, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Spacer()
                    MetricChip(value: "3", label: "active", tint: BoardPalette.signal)
                    MetricChip(value: "1", label: "waiting", tint: BoardPalette.amber)
                }
                taskRow("ESP32 work pulse", "Four-page navigation and device UX", BoardPalette.signal)
                taskRow("Mac companion", "Universal release pipeline verified", BoardPalette.signal)
                taskRow("Codex decisions", "Plan review needed on Mac", BoardPalette.amber)
                HStack(spacing: 12) {
                    Text("FOCUS")
                        .font(.board(11, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(BoardPalette.fog)
                    Text("Build the smallest safe next slice")
                        .font(.board(13, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Spacer()
                    Text("updated now")
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
                .padding(.horizontal, 16)
                .frame(height: 45)
                .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
        .padding(.vertical, 4)
    }

    private func taskRow(_ title: String, _ summary: String, _ tint: Color) -> some View {
        HStack(spacing: 15) {
            StatusDot(color: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.board(15, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Text(summary)
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
            }
            Spacer()
            Text(tint == BoardPalette.amber ? "REVIEW" : "ACTIVE")
                .font(.board(10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 17)
        .frame(height: 76)
        .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
