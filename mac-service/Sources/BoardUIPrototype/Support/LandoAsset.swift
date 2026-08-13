import AppKit
import Foundation

enum LandoAsset {
    static func image() -> NSImage {
        guard let location = Bundle.module.url(forResource: "lando_idle", withExtension: "png"),
              let image = NSImage(contentsOf: location) else {
            return NSImage()
        }
        return image
    }
}
