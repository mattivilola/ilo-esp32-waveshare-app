import BoardHostCore
import SwiftUI

struct XNewsFeedPreview: View {
    let feed: XNewsFeed?
    let isCurrent: Bool

    var body: some View {
        DisclosureGroup {
            if let feed, !feed.stories.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Label(
                        isCurrent ? "Ready to sync to the board" : "Expired cache · not sent to the board",
                        systemImage: isCurrent ? "checkmark.circle.fill" : "clock.badge.exclamationmark"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isCurrent ? .green : .orange)
                    .padding(.bottom, 8)

                    ForEach(Array(feed.stories.prefix(6).enumerated()), id: \.offset) { index, story in
                        if index > 0 { Divider().padding(.vertical, 8) }
                        storyRow(story)
                    }

                    if feed.stories.count > 6 {
                        Text("+ \(feed.stories.count - 6) more cached stories")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                }
                .padding(.top, 8)
            } else {
                Label("Available after the first accepted refresh", systemImage: "tray")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        } label: {
            Label("Board feed preview", systemImage: "rectangle.on.rectangle")
                .font(.caption.weight(.semibold))
        }
        .padding(.top, 4)
    }

    private func storyRow(_ story: XNewsStory) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                chip(story.category.rawValue, color: story.category == .ai ? .blue : .purple)
                chip(story.confidence.rawValue.capitalized, color: story.confidence == .high ? .green : .orange)
                Spacer(minLength: 4)
                if let source = story.sources.first {
                    Text(source.handle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(story.title)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(story.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}
