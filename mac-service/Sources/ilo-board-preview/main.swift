import AppKit
import BoardUIPrototype
import SwiftUI

@main
enum ILOBoardPreviewCommand {
    @MainActor
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "preview"
        do {
            switch command {
            case "preview":
                runPreview()
            case "screenshot":
                let page = try pageArgument(arguments)
                let output = value(after: "--output", in: arguments) ?? "artifacts/ui-previews/\(page.rawValue).png"
                try render(page, to: output)
            case "screenshots":
                let outputDirectory = value(after: "--output-dir", in: arguments) ?? "artifacts/ui-previews"
                for page in BoardPage.allCases {
                    try render(page, to: "\(outputDirectory)/\(page.rawValue).png")
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
    private static func runPreview() {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        let view = BoardDeviceView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 600),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ILO Board · 1024×600 UI Preview"
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
        application.run()
    }

    @MainActor
    private static func render(_ page: BoardPage, to path: String) throws {
        let renderer = ImageRenderer(content: BoardDeviceView(page: page, interactive: false))
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
        print("Rendered \(page.title): \(output.path)")
    }

    private static func pageArgument(_ arguments: [String]) throws -> BoardPage {
        guard let value = value(after: "--screen", in: arguments), let page = BoardPage(rawValue: value) else {
            throw PreviewError.invalidPage
        }
        return page
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

private enum PreviewError: LocalizedError {
    case invalidCommand(String)
    case invalidPage
    case renderFailed

    var errorDescription: String? {
        switch self {
        case let .invalidCommand(command): "Unknown command '\(command)'. Use preview, screenshot, or screenshots."
        case .invalidPage: "Pass --screen dashboard, codex, weather, or settings."
        case .renderFailed: "The 1024×600 UI preview could not be rendered."
        }
    }
}
