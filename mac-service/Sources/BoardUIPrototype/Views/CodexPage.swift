import SwiftUI

struct CodexPage: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Recent Codex tasks")
                    .font(.board(20, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                Spacer()
                MetricChip(value: "3", label: "recent", tint: BoardPalette.signal)
                MetricChip(value: "1", label: "attention", tint: BoardPalette.amber)
            }
            HStack(spacing: 16) {
                VStack(spacing: 10) {
                    codexRow("Set up ESP32 Mac controller", "History available · live Desktop state unavailable", BoardPalette.amber)
                    codexRow("Package macOS companion", "Completed locally · tests passed", BoardPalette.signal)
                    codexRow("Design work pulse UX", "In progress · simulator data", BoardPalette.signal)
                }
                PulseCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Safety boundary")
                        Text("READ ONLY")
                            .font(.board(26, weight: .bold))
                            .foregroundStyle(BoardPalette.signal)
                        Text("Recent task history can be shown safely. Approvals, answers and commands remain on the Mac.")
                            .font(.board(13))
                            .foregroundStyle(BoardPalette.fog)
                            .lineSpacing(5)
                        Spacer()
                        Divider().overlay(BoardPalette.steel)
                        statusLine("App Server", "LOCAL")
                        statusLine("Desktop tasks", "HISTORY")
                        statusLine("Remote actions", "OFF")
                    }
                }
                .frame(width: 290)
            }
        }
        .padding(.vertical, 4)
    }

    private func codexRow(_ title: String, _ detail: String, _ tint: Color) -> some View {
        PulseCard {
            HStack(spacing: 15) {
                StatusDot(color: tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.board(16, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text(detail)
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                Text(tint == BoardPalette.amber ? "CHECK MAC" : "ACTIVE")
                    .font(.board(10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(tint)
            }
        }
        .frame(height: 106)
    }

    private func statusLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.board(12))
                .foregroundStyle(BoardPalette.fog)
            Spacer()
            Text(value)
                .font(.board(11, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(BoardPalette.mist)
        }
    }
}
