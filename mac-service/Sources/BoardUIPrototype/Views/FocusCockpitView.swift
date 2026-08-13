import SwiftUI

struct FocusCockpitView: View {
    let minutes: Int
    let title: String
    let onDismiss: () -> Void
    @State private var totalSeconds: Int
    @State private var remainingSeconds: Int
    @State private var isPaused = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(minutes: Int, title: String, onDismiss: @escaping () -> Void) {
        self.minutes = minutes
        self.title = title
        self.onDismiss = onDismiss
        let seconds = minutes * 60
        _totalSeconds = State(initialValue: seconds)
        _remainingSeconds = State(initialValue: seconds)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            BoardPalette.carbon
            BoardPalette.signal.frame(width: 6)

            VStack(spacing: 0) {
                header
                HStack(spacing: 42) {
                    progressRing
                    detailPanel
                }
                .padding(.horizontal, 70)
                .frame(maxHeight: .infinity)
                Text("Tap a duration in Settings / hold it to start. Hold a Codex task to attach it.")
                    .font(.board(12, weight: .semibold))
                    .foregroundStyle(BoardPalette.fog)
                    .padding(.bottom, 28)
            }
        }
        .frame(width: 1024, height: 600)
        .onReceive(ticker) { _ in
            guard !isPaused, remainingSeconds > 0 else { return }
            remainingSeconds -= 1
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: BrandAsset.image())
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("ILO / FOCUS COCKPIT")
                    .font(.board(12, weight: .bold))
                    .tracking(1.3)
                    .foregroundStyle(BoardPalette.signal)
                Text("Battery-backed deadline / stays accurate through reset")
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
            }
            Spacer()
            Text(remainingSeconds == 0 ? "COMPLETE" : (isPaused ? "PAUSED" : "RTC BACKED"))
                .font(.board(11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(remainingSeconds == 0 ? BoardPalette.signal : (isPaused ? BoardPalette.amber : BoardPalette.cyan))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(BoardPalette.raised, in: Capsule())
        }
        .padding(.horizontal, 28)
        .frame(height: 88)
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(BoardPalette.steel, lineWidth: 24)
            Circle()
                .trim(from: 0, to: FocusPreviewMath.progress(
                    remainingSeconds: remainingSeconds,
                    totalSeconds: totalSeconds
                ))
                .stroke(BoardPalette.signal, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 8) {
                Text(FocusPreviewMath.countdown(remainingSeconds))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .foregroundStyle(BoardPalette.mist)
                Text(remainingSeconds == 0 ? "SESSION COMPLETE" : (isPaused ? "PAUSED / RTC SAFE" : "FOCUS / RTC BACKED"))
                    .font(.board(11, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(remainingSeconds == 0 || !isPaused ? BoardPalette.signal : BoardPalette.amber)
            }
        }
        .frame(width: 320, height: 320)
    }

    private var detailPanel: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title: "Selected work")
                Text(remainingSeconds == 0 ? "Your focus block is complete" : title)
                    .font(.board(21, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(3)
                    .padding(.top, 16)
                Spacer()
                Divider().overlay(BoardPalette.steel)
                Text("Pause safely, extend by five minutes, or hold to end.")
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
                    .padding(.vertical, 18)
                if remainingSeconds == 0 {
                    actionButton("RETURN TO BOARD", tint: BoardPalette.signal, action: onDismiss)
                } else {
                    HStack(spacing: 10) {
                        actionButton(isPaused ? "RESUME" : "PAUSE", tint: BoardPalette.signal) {
                            isPaused.toggle()
                        }
                        actionButton("+5 MIN", tint: BoardPalette.cyan) {
                            totalSeconds += 300
                            remainingSeconds += 300
                        }
                        Text("HOLD TO END")
                            .font(.board(11, weight: .bold))
                            .foregroundStyle(BoardPalette.carbon)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(BoardPalette.amber, in: RoundedRectangle(cornerRadius: 13))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.9, perform: onDismiss)
                    }
                }
            }
        }
        .frame(width: 500, height: 356)
    }

    private func actionButton(_ label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.board(11, weight: .bold))
                .foregroundStyle(BoardPalette.carbon)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(tint, in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }
}
