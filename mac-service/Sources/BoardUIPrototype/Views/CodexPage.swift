import SwiftUI

struct CodexPage: View {
    private enum FixedAction: String {
        case approve = "APPROVE"
        case reject = "REJECT"
        case `continue` = "CONTINUE"
    }

    @Binding var selectedTask: Int
    @State private var armedAction: FixedAction?
    @State private var sentAction: FixedAction?
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
                MetricChip(value: "10", label: "recent", tint: BoardPalette.signal)
                MetricChip(value: "1", label: "attention", tint: BoardPalette.amber)
            }
            HStack(spacing: 16) {
                Group {
                    if interactive {
                        ScrollView(.vertical) {
                            taskRows
                        }
                        .scrollIndicators(.visible)
                    } else {
                        GeometryReader { geometry in
                            taskRows
                                .frame(width: geometry.size.width, alignment: .top)
                        }
                        .clipped()
                    }
                }
                .frame(width: 650)
                .frame(maxHeight: .infinity)
                PulseCard {
                    VStack(alignment: .leading, spacing: 10) {
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
                        if let sentAction {
                            Text("SENT - \(sentAction.rawValue)")
                                .font(.board(11, weight: .bold))
                                .foregroundStyle(BoardPalette.signal)
                        } else if let armedAction {
                            Button("CONFIRM \(armedAction.rawValue)") {
                                self.armedAction = nil
                                sentAction = armedAction
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(BoardPalette.signal)
                        } else {
                            HStack(spacing: 8) {
                                ForEach(availableActions, id: \.rawValue) { action in
                                    Text("HOLD \(action.rawValue)")
                                        .font(.board(10, weight: .bold))
                                        .frame(maxWidth: .infinity, minHeight: 40)
                                        .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 10))
                                        .onLongPressGesture(minimumDuration: 0.9) {
                                            armedAction = action
                                        }
                                }
                            }
                        }
                        Text("OPEN CHAT")
                            .font(.board(11, weight: .bold))
                            .foregroundStyle(BoardPalette.mist)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 10))
                            .onTapGesture { showingChat = true }
                    }
                }
                .frame(width: 290)
            }
        }
    }

    private var taskRows: some View {
        VStack(spacing: 10) {
            ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                codexRow(index, task.title, task.detail, task.tint)
            }
        }
        .frame(maxWidth: .infinity)
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

            HStack(spacing: 16) {
                Group {
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
                }
                PulseCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(title: "Task details")
                        metadata("STATUS", taskStatus(selectedTask))
                        metadata("LAST UPDATED", selectedTask == 0 ? "14 AUG / 10:42" : "RECENT LOCAL ACTIVITY")
                        metadata("VISIBLE TEXT", "\(selectedChat.count) MESSAGES / LATEST SIX")
                        metadata(
                            "AVAILABLE ACTIONS",
                            availableActions.isEmpty
                                ? "NONE"
                                : availableActions.map(\.rawValue).joined(separator: " / ")
                        )
                        Spacer()
                        Text("Only recent user and Codex text is transferred.")
                            .font(.board(11))
                            .foregroundStyle(BoardPalette.fog)
                    }
                }
                .frame(width: 278)
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
            armedAction = nil
            sentAction = nil
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
        .frame(height: 88)
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.board(10, weight: .semibold))
                .foregroundStyle(BoardPalette.fog)
            Text(value)
                .font(.board(13, weight: .semibold))
                .foregroundStyle(BoardPalette.mist)
        }
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

    private var tasks: [(title: String, detail: String, tint: Color)] {
        [
            ("Improve Codex task controls", "Plan completed / approval decision available", BoardPalette.amber),
            ("Set up ESP32 Mac controller", "Idle / eligible to continue", BoardPalette.fog),
            ("Package macOS companion", "Completed locally / tests passed", BoardPalette.signal),
            ("Design work pulse UX", "In progress / simulator data", BoardPalette.signal),
            ("Verify OTA release flow", "Recent history / no remote action", BoardPalette.fog),
            ("Review touch targets", "Waiting for physical display check", BoardPalette.amber),
            ("Tune weather screen", "Completed / recent local task", BoardPalette.signal),
            ("Document USB fallback", "Idle / recent local task", BoardPalette.fog),
            ("Validate Pulse saver", "In progress / soak pending", BoardPalette.signal),
            ("Prepare release notes", "Recent history / no remote action", BoardPalette.fog),
        ]
    }

    private var availableActions: [FixedAction] {
        switch selectedTask {
        case 0: [.approve, .reject]
        case 1: [.continue]
        default: []
        }
    }

    private var selectedTaskTitle: String {
        tasks[min(max(selectedTask, 0), tasks.count - 1)].title
    }

    private var selectedTaskDetail: String {
        switch selectedTask {
        case 0: "The Mac re-fetches the latest completed plan before either fixed response."
        case 1: "The Mac constructs exactly: Please continue."
        default: "Recent chat is readable; no remote action is currently available."
        }
    }

    private func taskStatus(_ index: Int) -> String {
        switch index {
        case 0: "PLAN READY"
        case 1: "IDLE"
        case 2, 6: "DONE"
        case 3, 8: "ACTIVE"
        case 5: "WAITING"
        default: "RECENT"
        }
    }
}
