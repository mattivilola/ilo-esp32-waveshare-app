import Foundation

enum FocusPreviewMath {
    static func countdown(_ seconds: Int) -> String {
        let bounded = max(seconds, 0)
        return String(format: "%02d:%02d", bounded / 60, bounded % 60)
    }

    static func progress(remainingSeconds: Int, totalSeconds: Int) -> Double {
        guard totalSeconds > 0 else { return 1 }
        let remaining = min(max(remainingSeconds, 0), totalSeconds)
        return Double(totalSeconds - remaining) / Double(totalSeconds)
    }
}
