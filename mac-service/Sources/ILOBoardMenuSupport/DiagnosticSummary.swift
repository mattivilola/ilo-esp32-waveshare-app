import Foundation

public struct DiagnosticSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let appVersion: String
    public let macOSVersion: String
    public let serviceState: String
    public let launchAtLoginState: LaunchAtLoginState
    public let lastSync: Date?
    public let activity: [ConnectionHistoryEntry]

    public init(
        generatedAt: Date = Date(),
        appVersion: String,
        macOSVersion: String,
        serviceState: String,
        launchAtLoginState: LaunchAtLoginState,
        lastSync: Date?,
        activity: [ConnectionHistoryEntry]
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.serviceState = serviceState
        self.launchAtLoginState = launchAtLoginState
        self.lastSync = lastSync
        self.activity = activity
    }
}

public enum DiagnosticSummary {
    public static func render(_ snapshot: DiagnosticSnapshot) -> String {
        var lines = [
            "ILO Board diagnostics",
            "Generated: \(timestamp(snapshot.generatedAt))",
            "App version: \(snapshot.appVersion)",
            "macOS: \(snapshot.macOSVersion)",
            "Hardware profile: Waveshare ESP32-S3-Touch-LCD-5B (1024x600)",
            "Service: \(snapshot.serviceState)",
            "Launch at login: \(snapshot.launchAtLoginState.title)",
            "Last successful board sync: \(snapshot.lastSync.map(timestamp) ?? "Never")",
            "",
            "Recent activity:",
        ]

        if snapshot.activity.isEmpty {
            lines.append("- No recorded activity")
        } else {
            lines.append(contentsOf: snapshot.activity.prefix(10).map {
                "- \(timestamp($0.date)) — \($0.kind.title)"
            })
        }

        lines.append(contentsOf: [
            "",
            "Privacy: board identifiers, network addresses, ports, file paths, prompts, transcripts, and credentials are intentionally excluded.",
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
    }
}
