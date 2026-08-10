import SwiftUI

public struct BoardDeviceView: View {
    @State private var page: BoardPage
    private let interactive: Bool
    private let fixedPage: BoardPage?
    private let scenario: BoardPreviewScenario?

    public init(page: BoardPage = .dashboard, interactive: Bool = true) {
        _page = State(initialValue: page)
        self.interactive = interactive
        fixedPage = interactive ? nil : page
        scenario = nil
    }

    public init(scenario: BoardPreviewScenario) {
        _page = State(initialValue: scenario.page)
        interactive = false
        fixedPage = scenario.page
        self.scenario = scenario
    }

    public var body: some View {
        Group {
            if scenario == .sleep {
                BoardSleepValidationView()
            } else if scenario == .screensaver {
                BoardScreensaverValidationView()
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
        }
        .frame(width: 1024, height: 600)
        .contentShape(Rectangle())
        .gesture(swipeGesture)
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
                StatusDot(color: scenario?.connectionColor ?? BoardPalette.signal)
                Text(scenario?.connectionLabel ?? "MAC ONLINE")
                    .font(.board(12, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(BoardPalette.mist)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background((scenario?.connectionColor ?? BoardPalette.signal).opacity(0.12), in: Capsule())
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
            case .dashboard: DashboardPage()
            case .codex: CodexPage()
            case .xNews: XNewsPage()
            case .weather: WeatherPage()
            case .settings: SettingsPage()
            }
        }
    }

    private var navigation: some View {
        HStack(spacing: 8) {
            ForEach(BoardPage.allCases) { candidate in
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
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let pages = BoardPage.allCases
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
}
