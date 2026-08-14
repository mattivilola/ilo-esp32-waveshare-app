import SwiftUI

private struct FocusPreviewContext {
    let minutes: Int
    let title: String
}

public struct BoardDeviceView: View {
    @State private var page: BoardPage
    @State private var selectedCodexTask = 0
    @State private var focusContext: FocusPreviewContext?
    @State private var screensaverVisible = false
    private let interactive: Bool
    private let fixedPage: BoardPage?
    private let scenario: BoardPreviewScenario?
    private let codexEnabled: Bool
    private let xNewsEnabled: Bool
    private let codexChatOpen: Bool
    private let xNewsDetailOpen: Bool

    public init(
        page: BoardPage = .dashboard,
        interactive: Bool = true,
        codexEnabled: Bool = true,
        xNewsEnabled: Bool = true,
        codexChatOpen: Bool = false,
        xNewsDetailOpen: Bool = false
    ) {
        let initialPage = (!codexEnabled && page == .codex) || (!xNewsEnabled && page == .xNews)
            ? .weather
            : page
        _page = State(initialValue: initialPage)
        self.interactive = interactive
        fixedPage = interactive ? nil : initialPage
        scenario = nil
        self.codexEnabled = codexEnabled
        self.xNewsEnabled = xNewsEnabled
        self.codexChatOpen = codexChatOpen
        self.xNewsDetailOpen = xNewsDetailOpen
    }

    public init(scenario: BoardPreviewScenario) {
        _page = State(initialValue: scenario.page)
        interactive = false
        fixedPage = scenario.page
        self.scenario = scenario
        codexEnabled = true
        xNewsEnabled = true
        codexChatOpen = false
        xNewsDetailOpen = false
    }

    public init(focusMinutes: Int, focusTitle: String) {
        _page = State(initialValue: .dashboard)
        _focusContext = State(initialValue: FocusPreviewContext(minutes: focusMinutes, title: focusTitle))
        interactive = false
        fixedPage = .dashboard
        scenario = nil
        codexEnabled = true
        xNewsEnabled = true
        codexChatOpen = false
        xNewsDetailOpen = false
    }

    public var body: some View {
        Group {
            if scenario == .sleep {
                BoardSleepValidationView()
            } else if scenario == .screensaver || screensaverVisible {
                BoardScreensaverValidationView()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if interactive { screensaverVisible = false }
                    }
            } else {
                boardSurface
            }
        }
        .frame(width: 1024, height: 600)
        .environment(\.colorScheme, .dark)
    }

    private var boardSurface: some View {
        ZStack(alignment: .leading) {
            BoardPalette.carbon
            BoardPalette.signal.frame(width: 6)
            VStack(spacing: 0) {
                header
                pageContent
                    .padding(.horizontal, 22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                navigation
                    .padding(.horizontal, 22)
                    .frame(height: 58)
            }
            .padding(.leading, 6)
            if let focusContext {
                FocusCockpitView(minutes: focusContext.minutes, title: focusContext.title) {
                    self.focusContext = nil
                }
            }
        }
        .frame(width: 1024, height: 600)
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
        .animation(interactive ? .easeOut(duration: 0.18) : nil, value: visiblePage)
        .transaction { transaction in
            if !interactive { transaction.disablesAnimations = true }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: BrandAsset.image())
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(visiblePage.eyebrow)
                    .font(.board(12, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(BoardPalette.signal)
                Text(visiblePage.title)
                    .font(.board(18, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
            }
            Spacer()
            HStack(spacing: 8) {
                StatusDot(color: previewConnectionColor)
                Text(previewConnectionLabel)
                    .font(.board(12, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(BoardPalette.mist)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(previewConnectionColor.opacity(0.12), in: Capsule())
            Text("09:41")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(BoardPalette.fog)
        }
        .padding(.horizontal, 22)
        .frame(height: 68)
    }

    @ViewBuilder
    private var pageContent: some View {
        if let scenario {
            BoardValidationScenarioView(scenario: scenario)
        } else {
            switch visiblePage {
            case .dashboard:
                DashboardPage(
                    onOpenTask: { index in
                        guard interactive else { return }
                        selectedCodexTask = index
                        page = .codex
                    },
                    onOpenXNews: {
                        guard interactive else { return }
                        page = xNewsEnabled ? .xNews : (codexEnabled ? .codex : .weather)
                    },
                    onOpenWeather: {
                        guard interactive else { return }
                        page = .weather
                    },
                    onOpenSettings: {
                        guard interactive else { return }
                        page = .settings
                    },
                    onStartFocus: { index in
                        guard interactive else { return }
                        focusContext = FocusPreviewContext(
                            minutes: 25,
                            title: [
                                "Set up ESP32 Mac controller",
                                "Package macOS companion",
                                "Design work pulse UX",
                            ][min(max(index, 0), 2)]
                        )
                    },
                    codexEnabled: codexEnabled,
                    xNewsEnabled: xNewsEnabled
                )
            case .codex:
                CodexPage(
                    selectedTask: $selectedCodexTask,
                    initiallyShowingChat: codexChatOpen,
                    interactive: interactive
                )
            case .xNews:
                XNewsPage(interactive: interactive, initiallyShowingDetail: xNewsDetailOpen)
            case .weather: WeatherPage()
            case .settings:
                SettingsPage(
                    codexEnabled: codexEnabled,
                    xNewsEnabled: xNewsEnabled,
                    onStartFocus: { minutes in
                        guard interactive else { return }
                        focusContext = FocusPreviewContext(minutes: minutes, title: "Open focus session")
                    },
                    onShowScreensaver: {
                        guard interactive else { return }
                        screensaverVisible = true
                    }
                )
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            ForEach(visiblePages) { candidate in
                Button {
                    guard interactive else { return }
                    page = candidate
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(candidate == visiblePage ? BoardPalette.signal : BoardPalette.steel)
                            .frame(width: 7, height: 7)
                        Text(candidate.title)
                            .font(.board(12, weight: candidate == visiblePage ? .bold : .medium))
                    }
                    .foregroundStyle(candidate == visiblePage ? BoardPalette.mist : BoardPalette.fog)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(candidate == visiblePage ? BoardPalette.raised : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 35)
            .onEnded { value in
                guard interactive else { return }
                guard focusContext == nil else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let pages = visiblePages
                guard let index = pages.firstIndex(of: visiblePage) else { return }
                if value.translation.width < -55, index < pages.count - 1 {
                    page = pages[index + 1]
                } else if value.translation.width > 55, index > 0 {
                    page = pages[index - 1]
                }
            }
    }

    private var visiblePage: BoardPage {
        fixedPage ?? page
    }

    private var visiblePages: [BoardPage] {
        BoardPage.visiblePages(codexEnabled: codexEnabled, xNewsEnabled: xNewsEnabled)
    }

    private var previewConnectionLabel: String {
        scenario?.connectionLabel ?? (!codexEnabled && !xNewsEnabled ? "MAC OPTIONAL" : "MAC ONLINE")
    }

    private var previewConnectionColor: Color {
        scenario?.connectionColor ?? (!codexEnabled && !xNewsEnabled ? BoardPalette.fog : BoardPalette.signal)
    }
}
