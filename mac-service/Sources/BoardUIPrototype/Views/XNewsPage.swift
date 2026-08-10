import SwiftUI

struct XNewsPage: View {
    let interactive: Bool
    @State private var refreshState = PreviewRefreshState.idle
    @State private var pullDistance: CGFloat = 0
    @State private var refreshEligible = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0

    init(interactive: Bool = true) {
        self.interactive = interactive
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI + humanoid robotics")
                        .font(.board(20, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text(refreshSubtitle)
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                refreshIndicator
                verificationChip("5 CITED STORIES", tint: BoardPalette.signal)
                verificationChip("08:00", tint: BoardPalette.cyan)
            }

            GeometryReader { geometry in
                ZStack(alignment: .bottomTrailing) {
                    feedViewport

                    scrollIndicator(viewportHeight: geometry.size.height)

                    Text("SWIPE UP · 2 MORE  ↓")
                        .font(.board(9, weight: .bold))
                        .tracking(0.55)
                        .foregroundStyle(BoardPalette.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BoardPalette.carbon.opacity(0.92), in: Capsule())
                        .padding(.trailing, 16)
                        .padding(.bottom, 4)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .onAppear { scrollViewportHeight = geometry.size.height }
                .onChange(of: geometry.size.height) { scrollViewportHeight = $0 }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var feedViewport: some View {
        if interactive {
            ScrollView(.vertical, showsIndicators: false) {
                feedContent
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: XNewsScrollMetricsKey.self,
                                value: XNewsScrollMetrics(
                                    offset: geometry.frame(in: .named("x-news-scroll-space")).minY,
                                    contentHeight: geometry.size.height
                                )
                            )
                        }
                    }
                    .background(PointerDragScrollBridge())
            }
            .accessibilityIdentifier("x-news-scroll")
            .coordinateSpace(name: "x-news-scroll-space")
            .onPreferenceChange(XNewsScrollMetricsKey.self) { metrics in
                scrollOffset = metrics.offset
                scrollContentHeight = metrics.contentHeight
            }
            .simultaneousGesture(refreshGesture)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            feedContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
    }

    private var refreshSubtitle: String {
        switch refreshState {
        case .idle:
            pullDistance >= 72 ? "Release to fetch the latest verified stories" : "Rolling 24 hours · pull down to refresh"
        case .fetching:
            "Fetching latest AI + robotics news via the Mac…"
        case .updated:
            "Updated now · timestamps and direct citations verified"
        }
    }

    @ViewBuilder
    private var refreshIndicator: some View {
        HStack(spacing: 6) {
            switch refreshState {
            case .fetching:
                ProgressView()
                    .controlSize(.small)
                    .tint(BoardPalette.signal)
                Text("REFRESHING")
            case .updated:
                Image(systemName: "checkmark.circle.fill")
                Text("UPDATED")
            case .idle:
                Image(systemName: pullDistance >= 72 ? "arrow.down.circle.fill" : "arrow.down.circle")
                Text(pullDistance >= 72 ? "RELEASE" : "PULL TO REFRESH")
            }
        }
        .font(.board(9, weight: .bold))
        .tracking(0.5)
        .foregroundStyle(refreshState == .updated ? BoardPalette.cyan : BoardPalette.signal)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(BoardPalette.signal.opacity(0.11), in: Capsule())
    }

    private func scrollIndicator(viewportHeight: CGFloat) -> some View {
        let trackHeight = max(viewportHeight - 16, 1)
        let maximumOffset = max(scrollContentHeight - scrollViewportHeight, 1)
        let progress = min(max(-scrollOffset / maximumOffset, 0), 1)
        let thumbHeight = max(38, trackHeight * min(scrollViewportHeight / max(scrollContentHeight, 1), 1))
        let thumbTravel = max(trackHeight - thumbHeight, 0)

        return Capsule()
            .fill(BoardPalette.steel.opacity(0.48))
            .frame(width: 5, height: trackHeight)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(BoardPalette.cyan)
                    .frame(width: 5, height: thumbHeight)
                    .offset(y: thumbTravel * progress)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
            .allowsHitTesting(false)
            .opacity(scrollContentHeight > scrollViewportHeight + 1 ? 1 : 0)
    }

    private var refreshGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard interactive, refreshState != .fetching else { return }
                if pullDistance == 0 {
                    refreshEligible = scrollOffset >= -2
                }
                guard refreshEligible,
                      value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width)
                else {
                    return
                }
                pullDistance = min(value.translation.height, 96)
            }
            .onEnded { _ in
                defer {
                    pullDistance = 0
                    refreshEligible = false
                }
                guard interactive, refreshState == .idle, pullDistance >= 72 else { return }
                refreshState = .fetching
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    refreshState = .updated
                    try? await Task.sleep(for: .seconds(1.4))
                    refreshState = .idle
                }
            }
    }

    private var feedContent: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                featuredStory
                    .frame(width: 430)
                VStack(spacing: 12) {
                    compactStory(
                        category: "ROBOTICS",
                        title: "Humanoid pilot moves from demo to measured factory trial",
                        source: "@primary_source · 43 min",
                        tint: BoardPalette.cyan
                    )
                    compactStory(
                        category: "AI",
                        title: "New multimodal model targets real-time physical control",
                        source: "@research_lab · 2 hr",
                        tint: BoardPalette.signal
                    )
                }
            }
            .frame(height: 326)

            verificationFooter

            HStack(spacing: 14) {
                compactStory(
                    category: "ROBOTICS",
                    title: "Dexterous gripper study reports repeatable manipulation gains",
                    source: "@robotics_lab · 4 hr",
                    tint: BoardPalette.cyan
                )
                compactStory(
                    category: "AI",
                    title: "Efficient vision stack reaches a new edge-device milestone",
                    source: "@edge_ai · 6 hr",
                    tint: BoardPalette.signal
                )
            }
            .frame(height: 148)
            .padding(.bottom, 24)
        }
    }

    private var verificationFooter: some View {
        HStack(spacing: 8) {
            StatusDot(color: BoardPalette.signal)
            Text("DIRECT X POSTS · TIMESTAMPS CHECKED LOCALLY")
                .font(.board(10, weight: .bold))
                .tracking(0.65)
                .foregroundStyle(BoardPalette.fog)
            Spacer()
            Text("SAMPLE CONTRACT · GROK VIA MAC")
                .font(.board(10, weight: .bold))
                .tracking(0.65)
                .foregroundStyle(BoardPalette.amber)
        }
        .padding(.horizontal, 4)
    }

    private var featuredStory: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    verificationChip("AI · HIGH", tint: BoardPalette.signal)
                    Spacer()
                    Text("18 MIN")
                        .font(.board(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(BoardPalette.fog)
                }
                Text("Open model release improves compact on-device reasoning")
                    .font(.board(22, weight: .bold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The primary-source post includes release details and measured results. The board receives only this bounded summary and its verified citation.")
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
                    .lineSpacing(4)
                    .lineLimit(3)
                Spacer()
                Divider().overlay(BoardPalette.steel)
                HStack {
                    Text("@model_lab")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BoardPalette.cyan)
                    Spacer()
                    Text("1 DIRECT POST")
                        .font(.board(10, weight: .bold))
                        .tracking(0.65)
                        .foregroundStyle(BoardPalette.signal)
                }
            }
        }
    }

    private func compactStory(category: String, title: String, source: String, tint: Color) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(category)
                        .font(.board(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("VERIFIED")
                        .font(.board(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(BoardPalette.signal)
                }
                Text(title)
                    .font(.board(15, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(2)
                Spacer()
                Text(source)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoardPalette.fog)
            }
        }
    }

    private func verificationChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.board(10, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
    }
}

private enum PreviewRefreshState {
    case idle
    case fetching
    case updated
}

private struct XNewsScrollMetrics: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
}

private struct XNewsScrollMetricsKey: PreferenceKey {
    static let defaultValue = XNewsScrollMetrics(offset: 0, contentHeight: 0)

    static func reduce(value: inout XNewsScrollMetrics, nextValue: () -> XNewsScrollMetrics) {
        value = nextValue()
    }
}
