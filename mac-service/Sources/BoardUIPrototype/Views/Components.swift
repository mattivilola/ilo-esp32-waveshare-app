import SwiftUI

struct PulseCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BoardPalette.steel.opacity(0.42), lineWidth: 1)
            }
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.board(12, weight: .bold))
            .tracking(1.2)
            .foregroundStyle(BoardPalette.fog)
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .shadow(color: color.opacity(0.35), radius: 5)
    }
}

struct MetricChip: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Text(value)
                .font(.board(20, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.board(12, weight: .semibold))
                .foregroundStyle(BoardPalette.fog)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(BoardPalette.raised, in: Capsule())
    }
}

struct DeviceSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(value, 0), 1)
            let knobX = max(9, min(geometry.size.width - 9, geometry.size.width * clamped))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BoardPalette.steel)
                    .frame(height: 6)
                Capsule()
                    .fill(BoardPalette.signal)
                    .frame(width: knobX, height: 6)
                Circle()
                    .fill(BoardPalette.mist)
                    .frame(width: 18, height: 18)
                    .shadow(color: BoardPalette.signal.opacity(0.35), radius: 4)
                    .offset(x: knobX - 9)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { change in
                        value = min(max(change.location.x / geometry.size.width, 0), 1)
                    }
            )
        }
        .frame(height: 20)
    }
}

struct DeviceToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? BoardPalette.signal : BoardPalette.steel)
                .frame(width: 48, height: 27)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(BoardPalette.mist)
                        .frame(width: 21, height: 21)
                        .padding(3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Privacy mode")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}
