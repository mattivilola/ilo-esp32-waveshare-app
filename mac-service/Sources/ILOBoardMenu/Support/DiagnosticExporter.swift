import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DiagnosticExporter {
    static func copy(_ summary: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)
    }

    static func save(_ summary: String, completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        panel.title = "Save ILO Board Diagnostics"
        panel.nameFieldStringValue = "ILO-Board-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            do {
                try summary.write(to: url, atomically: true, encoding: .utf8)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}
