import SwiftUI

enum BoardPalette {
    static let carbon = Color(red: 0.039, green: 0.059, blue: 0.078)
    static let slate = Color(red: 0.075, green: 0.106, blue: 0.133)
    static let raised = Color(red: 0.098, green: 0.137, blue: 0.169)
    static let steel = Color(red: 0.141, green: 0.192, blue: 0.235)
    static let signal = Color(red: 0.396, green: 0.898, blue: 0.722)
    static let cyan = Color(red: 0.216, green: 0.702, blue: 0.851)
    static let amber = Color(red: 1.0, green: 0.710, blue: 0.353)
    static let mist = Color(red: 0.953, green: 0.969, blue: 0.973)
    static let fog = Color(red: 0.557, green: 0.635, blue: 0.698)
}

extension Font {
    static func board(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
