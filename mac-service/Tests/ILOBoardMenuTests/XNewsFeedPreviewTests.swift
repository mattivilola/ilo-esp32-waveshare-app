@testable import ILOBoardMenu
import BoardHostCore
import Foundation
import Testing

@MainActor
@Test func companionLoadsExpiredFeedForClearlyMarkedBoardPreview() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ilo-board-menu-news-preview-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = XNewsFeedCache(url: directory.appendingPathComponent("feed.json"))
    let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let story = XNewsStory(
        title: "Robotics preview",
        summary: "A bounded story shown in the Mac companion.",
        postText: "A bounded story shown in the Mac companion.",
        category: .robotics,
        confidence: .high,
        sources: [XNewsCitation(
            handle: "@robotics",
            postedAt: generatedAt,
            xURL: URL(string: "https://x.com/robotics/status/123456789")!
        )]
    )
    try cache.save(XNewsFeed(generatedAt: generatedAt, stories: [story]))
    let settingsStore = XNewsRefreshSettingsStore(url: directory.appendingPathComponent("settings.json"))
    try settingsStore.save(XNewsRefreshSettings(cadence: .daily))
    let defaults = try #require(UserDefaults(suiteName: "ilo-board-news-preview-\(UUID().uuidString)"))
    let store = HostStatusStore(
        defaults: defaults,
        xNewsFeatureController: XNewsFeatureController(
            settingsStore: settingsStore,
            apiKeyConfigured: true
        ),
        xNewsFeedCache: cache,
        autoStart: false
    )

    store.refreshXNewsStatus()

    #expect(store.xNewsCachedStoryCount == 1)
    #expect(store.xNewsCachedFeed?.stories.first?.title == "Robotics preview")
    #expect(store.xNewsCacheIsCurrent == false)
}
