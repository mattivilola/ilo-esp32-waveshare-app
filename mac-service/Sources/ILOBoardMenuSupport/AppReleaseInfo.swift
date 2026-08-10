import Foundation

public struct AppReleaseInfo: Equatable, Sendable {
    public let marketingVersion: String
    public let buildNumber: String?

    public init(marketingVersion: String, buildNumber: String?) {
        self.marketingVersion = marketingVersion
        self.buildNumber = buildNumber
    }

    public init(infoDictionary: [String: Any]?) {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String
        let build = infoDictionary?["CFBundleVersion"] as? String
        marketingVersion = version?.isEmpty == false ? version! : "development"
        buildNumber = build?.isEmpty == false ? build : nil
    }

    public var displayVersion: String {
        buildNumber.map { "\(marketingVersion) (\($0))" } ?? marketingVersion
    }
}
