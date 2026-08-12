import SwiftUI

struct CodexPage: View {
    @Binding var selectedTask: Int
    @State private var continueArmed = false
    @State private var continueSent = false

    init(selectedTask: Binding<Int> = .constant(0)) {
        _selectedTask = selectedTask
    }

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
                    codexRow(0, "Set up ESP32 Mac controller", "History available / eligible to continue", BoardPalette.fog)
                    codexRow(1, "Package macOS companion", "Completed locally / tests passed", BoardPalette.signal)
                    codexRow(2, "Design work pulse UX", "In progress / simulator data", BoardPalette.signal)
                }
                PulseCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel(title: "Related chat")
                        Text(selectedTask == 0 ? "Set up ESP32 Mac controller" : "Action unavailable")
                            .font(.board(19, weight: .bold))
                            .foregroundStyle(BoardPalette.mist)
                            .lineLimit(2)
                        Text(selectedTask == 0
                            ? "The Mac constructs exactly: Please continue."
                            : "Only idle recent tasks can use the fixed continue action.")
                            .font(.board(13))
                            .foregroundStyle(BoardPalette.fog)
                            .lineSpacing(5)
                        Spacer()
                        if selectedTask == 0 {
                            Text(continueSent ? "SENT - CODEX IS CONTINUING" : (continueArmed ? "ARMED - TAP CONFIRM" : "HOLD, THEN CONFIRM"))
                                .font(.board(11, weight: .bold))
                                .foregroundStyle(continueSent ? BoardPalette.signal : BoardPalette.fog)
                            if continueArmed {
                                Button("CONFIRM CONTINUE") {
                                    continueArmed = false
                                    continueSent = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(BoardPalette.signal)
                            } else if !continueSent {
                                Text("HOLD TO ARM")
                                    .font(.board(12, weight: .bold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 12))
                                    .onLongPressGesture(minimumDuration: 0.9) {
                                        continueArmed = true
                                    }
                            }
                        }
                    }
                }
                .frame(width: 290)
            }
        }
        .padding(.vertical, 4)
    }

    private func codexRow(_ index: Int, _ title: String, _ detail: String, _ tint: Color) -> some View {
        Button {
            selectedTask = index
            continueArmed = false
            continueSent = false
        } label: {
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
                Text(index == 0 ? "IDLE" : "ACTIVE")
                    .font(.board(10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(tint)
            }
        }
        }
        .buttonStyle(.plain)
        .frame(height: 106)
    }
}
