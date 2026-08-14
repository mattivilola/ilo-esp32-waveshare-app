import SwiftUI

struct XNewsPage: View {
    let interactive: Bool
    @State private var refreshState = PreviewRefreshState.idle
    @State private var pullDistance: CGFloat = 0
    @State private var refreshEligible = false
    @State private var scrollOffset: CGFloat = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var selectedStory: PreviewXNewsStory?

    init(interactive: Bool = true, initiallyShowingDetail: Bool = false) {
        self.interactive = interactive
        _selectedStory = State(initialValue: initiallyShowingDetail ? PreviewXNewsStory.samples[0] : nil)
    }

    var body: some View {
        ZStack {
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
                    metadataChip("15 POSTS", tint: BoardPalette.signal)
                    metadataChip("08:00", tint: BoardPalette.cyan)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .bottomTrailing) {
                        feedViewport
                        scrollIndicator(viewportHeight: geometry.size.height)

                        Text("SWIPE UP · 12 MORE  ↓")
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

            if let selectedStory {
                detailView(selectedStory)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .animation(.easeOut(duration: 0.18), value: selectedStory)
    }

    @ViewBuilder
    private var feedViewport: some View {
        if interactive {
            ScrollViewReader { proxy in
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
                .onAppear {
                    proxy.scrollTo(PreviewXNewsStory.samples[0].id, anchor: .top)
                }
            }
        } else {
            GeometryReader { geometry in
                feedContent
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
            .clipped()
        }
    }

    private var refreshSubtitle: String {
        switch refreshState {
        case .idle:
            pullDistance >= 72 ? "Release to fetch the latest posts" : "Rolling 24 hours · pull down to refresh"
        case .fetching:
            "Fetching latest AI + robotics news via the Mac…"
        case .updated:
            "Updated now · direct X posts ready"
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
        VStack(spacing: 0) {
            ForEach(PreviewXNewsStory.samples) { story in
                Button {
                    guard interactive else { return }
                    selectedStory = story
                } label: {
                    storyRow(story)
                }
                .buttonStyle(.plain)
                .id(story.id)
                Divider().overlay(BoardPalette.steel)
            }
        }
        .padding(.trailing, 12)
        .padding(.bottom, 24)
    }

    private func storyRow(_ story: PreviewXNewsStory) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                Text(story.title)
                    .font(.board(16, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(1)
                Spacer(minLength: 12)
                metadataChip(story.category, tint: story.categoryTint)
                metadataChip(story.confidence, tint: story.confidenceTint)
            }
            Text(story.summary)
                .font(.board(12))
                .foregroundStyle(BoardPalette.fog)
                .lineLimit(1)
            HStack {
                Text(story.handle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(BoardPalette.cyan)
                Text("· \(story.age)")
                    .font(.board(11))
                    .foregroundStyle(BoardPalette.fog)
                Spacer()
                Text("READ POST  →")
                    .font(.board(10, weight: .bold))
                    .tracking(0.55)
                    .foregroundStyle(BoardPalette.fog)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .background(BoardPalette.slate.opacity(0.42))
    }

    private func detailView(_ story: PreviewXNewsStory) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    selectedStory = nil
                } label: {
                    Label("BACK", systemImage: "chevron.left")
                        .font(.board(12, weight: .bold))
                        .foregroundStyle(BoardPalette.mist)
                        .frame(width: 118, height: 46)
                        .background(BoardPalette.steel, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text(story.handle)
                        .font(.board(18, weight: .semibold))
                        .foregroundStyle(BoardPalette.cyan)
                    Text(story.timestamp)
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                metadataChip(story.category, tint: story.categoryTint)
                metadataChip(story.confidence, tint: story.confidenceTint)
            }

            Group {
                if interactive {
                    ScrollView(.vertical, showsIndicators: true) {
                        detailContent(story)
                    }
                } else {
                    detailContent(story)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipped()
                }
            }
            .background(BoardPalette.slate.opacity(0.54), in: RoundedRectangle(cornerRadius: 16))

            Text("SWIPE TO READ · COMPLETE AVAILABLE POST TEXT · READ ONLY")
                .font(.board(9, weight: .bold))
                .tracking(0.55)
                .foregroundStyle(BoardPalette.fog)
        }
        .padding(.vertical, 4)
        .background(BoardPalette.carbon)
    }

    private func detailContent(_ story: PreviewXNewsStory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(story.title)
                .font(.board(26, weight: .bold))
                .foregroundStyle(BoardPalette.mist)
            detailSection("WHY IT MATTERS", text: story.summary, tint: BoardPalette.signal)
            detailSection("X POST", text: story.postText, tint: BoardPalette.cyan)
            VStack(alignment: .leading, spacing: 6) {
                Text("DIRECT SOURCE")
                    .font(.board(10, weight: .bold))
                    .tracking(0.65)
                    .foregroundStyle(BoardPalette.fog)
                Text(story.url)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoardPalette.cyan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func detailSection(_ label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.board(10, weight: .bold))
                .tracking(0.65)
                .foregroundStyle(tint)
            Text(text)
                .font(.board(15))
                .foregroundStyle(label == "X POST" ? BoardPalette.mist : BoardPalette.fog)
                .lineSpacing(5)
        }
    }

    private func metadataChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.board(9, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.11), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.34), lineWidth: 1))
    }
}

private struct PreviewXNewsStory: Identifiable, Equatable {
    let id: Int
    let category: String
    let confidence: String
    let title: String
    let summary: String
    let postText: String
    let handle: String
    let age: String
    let timestamp: String
    let url: String

    var categoryTint: Color { category == "ROBOTICS" ? BoardPalette.cyan : BoardPalette.signal }
    var confidenceTint: Color { confidence == "MEDIUM" ? BoardPalette.amber : BoardPalette.signal }

    static let samples: [Self] = {
        let titles = [
            "Open model release improves compact on-device reasoning",
            "Humanoid pilot moves from demo to measured factory trial",
            "New multimodal model targets real-time physical control",
            "Dexterous gripper study reports repeatable manipulation gains",
            "Efficient vision stack reaches a new edge-device milestone",
            "Agent tooling release adds a bounded local execution mode",
            "Mobile manipulator benchmark publishes new field results",
            "Open evaluation suite expands multimodal reasoning tests",
            "Warehouse robot fleet adds shared spatial memory",
            "Small language model reaches a new latency target",
            "Humanoid hand design publishes repeatability results",
            "Vision-language policy improves zero-shot tool use",
            "Robotics simulator adds contact-rich training scenes",
            "On-device agent framework introduces offline planning",
            "Biped controller reports longer untethered field runs",
        ]
        return titles.enumerated().map { index, title in
            let robotics = [1, 3, 6, 8, 10, 12, 14].contains(index)
            let handle = robotics ? "@robot_lab_\(index + 1)" : "@ai_lab_\(index + 1)"
            return Self(
                id: index,
                category: robotics ? "ROBOTICS" : "AI",
                confidence: index.isMultiple(of: 4) ? "MEDIUM" : "HIGH",
                title: title,
                summary: "A concise explanation of the development and why it belongs in today's rolling brief.",
                postText: "We are sharing the complete available text of this sample X post. It includes the announcement, the concrete result, and the context needed to understand what changed without leaving the board.\n\nThe direct source remains visible below for follow-up on another device.",
                handle: handle,
                age: "\(index + 1) hr",
                timestamp: "14 AUG 2026 · \(String(format: "%02d", 8 + (index % 8))):20 UTC",
                url: "https://x.com/\(handle.dropFirst())/status/19500000000000000\(index)")
        }
    }()
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
