import AppKit
import BoardUIPrototype
import SwiftUI

@main
enum ILOBoardPreviewCommand {
    @MainActor private static var previewWindowDelegate: PreviewWindowDelegate?

    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "preview"
        do {
            switch command {
            case "preview":
                runPreview(arguments: arguments)
            case "screenshot":
                let page = try pageArgument(arguments)
                let output = value(after: "--output", in: arguments) ?? "artifacts/ui-previews/\(page.rawValue).png"
                try render(page, codexChatOpen: arguments.contains("--chat"), to: output)
            case "screenshots":
                let outputDirectory = value(after: "--output-dir", in: arguments) ?? "artifacts/ui-previews"
                for page in BoardPage.allCases {
                    try render(page, to: "\(outputDirectory)/\(page.rawValue).png")
                }
            case "scenario-screenshot":
                let scenario = try scenarioArgument(arguments)
                let output = value(after: "--output", in: arguments) ?? "artifacts/ui-states/\(scenario.rawValue).png"
                try render(scenario, to: output)
            case "scenario-screenshots":
                let outputDirectory = value(after: "--output-dir", in: arguments) ?? "artifacts/ui-states"
                for scenario in BoardPreviewScenario.allCases {
                    try render(scenario, to: "\(outputDirectory)/\(scenario.rawValue).png")
                }
            default:
                throw PreviewError.invalidCommand(command)
            }
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func runPreview(arguments: [String]) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let view = BoardDeviceView(
            page: arguments.contains("--chat") ? .codex : .dashboard,
            xNewsEnabled: !arguments.contains("--without-x-news"),
            codexChatOpen: arguments.contains("--chat")
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ILO Board · 1024×600 UI Preview"
        let windowDelegate = PreviewWindowDelegate()
        previewWindowDelegate = windowDelegate
        window.delegate = windowDelegate
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        application.run()
    }

    @MainActor
    private static func render(_ page: BoardPage, codexChatOpen: Bool = false, to path: String) throws {
        try render(
            BoardDeviceView(page: page, interactive: false, codexChatOpen: codexChatOpen),
            label: codexChatOpen ? "Codex chat" : page.title,
            to: path
        )
    }

    @MainActor
    private static func render(_ scenario: BoardPreviewScenario, to path: String) throws {
        try render(BoardDeviceView(scenario: scenario), label: scenario.title, to: path)
    }

    @MainActor
    private static func render<Content: View>(_ content: Content, label: String, to path: String) throws {
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 1024, height: 600)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            throw PreviewError.renderFailed
        }
        let output = URL(fileURLWithPath: path, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: output, options: .atomic)
        print("Rendered \(label): \(output.path)")
    }

    private static func pageArgument(_ arguments: [String]) throws -> BoardPage {
        guard let value = value(after: "--screen", in: arguments), let page = BoardPage(rawValue: value) else {
            throw PreviewError.invalidPage
        }
        return page
    }

    private static func scenarioArgument(_ arguments: [String]) throws -> BoardPreviewScenario {
        guard let value = value(after: "--scenario", in: arguments),
              let scenario = BoardPreviewScenario(rawValue: value)
        else {
            throw PreviewError.invalidScenario
        }
        return scenario
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private final class PreviewWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.terminate(nil)
    }
}

private enum PreviewError: LocalizedError {
    case invalidCommand(String)
    case invalidPage
    case invalidScenario
    case renderFailed

    var errorDescription: String? {
        switch self {
        case let .invalidCommand(command): "Unknown command '\(command)'. Use preview, screenshot, screenshots, scenario-screenshot, or scenario-screenshots."
        case .invalidPage: "Pass --screen dashboard, codex, x-news, weather, or settings."
        case .invalidScenario: "Pass --scenario offline, loading, stale, error, long-text, privacy, sleep, reconnect, screensaver, or approval-request."
        case .renderFailed: "The 1024×600 UI preview could not be rendered."
        }
    }
}
