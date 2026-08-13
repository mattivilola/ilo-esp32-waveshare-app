import SwiftUI

struct CodexPage: View {
    @Binding var selectedTask: Int
    @State private var continueArmed = false
    @State private var continueSent = false
    @State private var showingChat: Bool
    private let interactive: Bool

    init(
        selectedTask: Binding<Int> = .constant(0),
        initiallyShowingChat: Bool = false,
        interactive: Bool = true
    ) {
        _selectedTask = selectedTask
        _showingChat = State(initialValue: initiallyShowingChat)
        self.interactive = interactive
    }

    var body: some View {
        Group {
            if showingChat {
                chatReader
            } else {
                taskBrowser
            }
        }
        .padding(.vertical, 4)
    }

    private var taskBrowser: some View {
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
                        Text(selectedTaskTitle)
                            .font(.board(19, weight: .bold))
                            .foregroundStyle(BoardPalette.mist)
                            .lineLimit(2)
                        Text(selectedTaskDetail)
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
    }

    private var chatReader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    showingChat = false
                } label: {
                    Label("BACK", systemImage: "chevron.left")
                        .font(.board(12, weight: .bold))
                        .frame(width: 104)
                        .frame(minHeight: 42)
                }
                .buttonStyle(.plain)
                .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedTaskTitle)
                        .font(.board(19, weight: .bold))
                        .foregroundStyle(BoardPalette.mist)
                        .lineLimit(1)
                    Text("RECENT CONVERSATION / USER + CODEX TEXT")
                        .font(.board(10, weight: .semibold))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                Text("READ ONLY")
                    .font(.board(11, weight: .bold))
                    .foregroundStyle(BoardPalette.signal)
            }

            if interactive {
                ScrollView(.vertical) {
                    chatMessages
                }
                .scrollIndicators(.visible)
            } else {
                chatMessages
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipped()
            }

            Text("SWIPE UP/DOWN  /  LATEST SIX  /  READ ONLY")
                .font(.board(10, weight: .semibold))
                .foregroundStyle(BoardPalette.fog)
        }
    }

    private var chatMessages: some View {
        VStack(spacing: 10) {
            ForEach(Array(selectedChat.enumerated()), id: \.offset) { _, message in
                VStack(alignment: .leading, spacing: 7) {
                    Text(message.user ? "YOU" : "CODEX")
                        .font(.board(10, weight: .bold))
                        .foregroundStyle(message.user ? BoardPalette.cyan : BoardPalette.signal)
                    Text(message.text)
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.mist)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(15)
                .background(
                    message.user ? BoardPalette.steel : BoardPalette.slate,
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
        }
    }

    private func codexRow(_ index: Int, _ title: String, _ detail: String, _ tint: Color) -> some View {
        Button {
            selectedTask = index
            continueArmed = false
            continueSent = false
            showingChat = true
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
                Text(taskStatus(index))
                    .font(.board(10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .foregroundStyle(BoardPalette.fog)
            }
        }
        }
        .buttonStyle(.plain)
        .frame(height: 106)
    }

    private var selectedChat: [(user: Bool, text: String)] {
        switch selectedTask {
        case 1:
            [
                (true, "Please package the latest Mac companion and verify its update path."),
                (false, "The universal app is signed, notarized, and its public update artifact matches byte-for-byte."),
                (true, "Great. Keep the rollout notes concise."),
                (false, "Done. The release status and exact update path are ready."),
            ]
        case 2:
            [
                (true, "Can the board show a clearer view of ongoing work?"),
                (false, "Yes. The work pulse now keeps task identity visible and uses a focused detail surface."),
            ]
        default:
            [
                (true, "Can we read more of the Codex chat when opening a task?"),
                (false, "I can add an on-demand recent-chat view that transfers only visible user and assistant text."),
                (true, "Make it simple and let me scroll up and down."),
                (false, "The task now opens a full-width, read-only chat reader with native vertical swipe scrolling."),
            ]
        }
    }

    private var selectedTaskTitle: String {
        switch selectedTask {
        case 1: "Package macOS companion"
        case 2: "Design work pulse UX"
        default: "Set up ESP32 Mac controller"
        }
    }

    private var selectedTaskDetail: String {
        switch selectedTask {
        case 1: "Completed locally / tests passed. Continue is unavailable."
        case 2: "Plan review needed on Mac. Continue is unavailable."
        default: "The Mac constructs exactly: Please continue."
        }
    }

    private func taskStatus(_ index: Int) -> String {
        switch index {
        case 1: "DONE"
        case 2: "REVIEW"
        default: "IDLE"
        }
    }
}
