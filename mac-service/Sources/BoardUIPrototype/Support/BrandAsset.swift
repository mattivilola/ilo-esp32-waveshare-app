import AppKit
import Foundation

enum BrandAsset {
    static func image() -> NSImage {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            Bundle.main.url(forResource: "icon_round", withExtension: "png"),
            root.appendingPathComponent("mac-service/Sources/ILOBoardMenu/Resources/icon_round.png"),
        ]
        for location in candidates {
            if let location, let image = NSImage(contentsOf: location) {
                return image
            }
        }
        return NSImage()
    }
}
