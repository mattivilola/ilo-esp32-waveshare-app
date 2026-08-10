import AppKit
import Foundation

enum BrandImage {
    static let image: NSImage = {
        let packaged = Bundle.main.url(forResource: "icon_round", withExtension: "png")
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mac-service/Sources/ILOBoardMenu/Resources/icon_round.png")
        for location in [packaged, development] {
            if let location, let image = NSImage(contentsOf: location) {
                return image
            }
        }
        return NSImage(systemSymbolName: "rectangle.connected.to.line.below", accessibilityDescription: "ILO Board")
            ?? NSImage()
    }()
}
