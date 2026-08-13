import SwiftUI

struct DashboardPage: View {
    let onOpenTask: (Int) -> Void
    let onOpenXNews: () -> Void
    let onOpenWeather: () -> Void
    let onOpenSettings: () -> Void
    let onStartFocus: (Int) -> Void
    let codexEnabled: Bool
    let xNewsEnabled: Bool

    init(
        onOpenTask: @escaping (Int) -> Void = { _ in },
        onOpenXNews: @escaping () -> Void = {},
        onOpenWeather: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onStartFocus: @escaping (Int) -> Void = { _ in },
        codexEnabled: Bool = true,
        xNewsEnabled: Bool = true
    ) {
        self.onOpenTask = onOpenTask
        self.onOpenXNews = onOpenXNews
        self.onOpenWeather = onOpenWeather
        self.onOpenSettings = onOpenSettings
        self.onStartFocus = onStartFocus
        self.codexEnabled = codexEnabled
        self.xNewsEnabled = xNewsEnabled
    }

    @ViewBuilder
    var body: some View {
        if codexEnabled {
            codexDashboard
        } else {
            standaloneDashboard
        }
    }

    private var codexDashboard: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(title: "Attention")
                    Text("1")
                        .font(.board(78, weight: .bold))
                        .foregroundStyle(BoardPalette.amber)
                        .padding(.top, 10)
                    Text("Codex needs review")
                        .font(.board(18, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text("One plan is waiting on your Mac")
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.fog)
                        .padding(.top, 6)
                    Spacer()
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(title: "MacBook power")
                            Text("Charging")
                                .font(.board(13, weight: .semibold))
                                .foregroundStyle(BoardPalette.signal)
                        }
                        Spacer()
                        Text("82%")
                            .font(.board(25, weight: .bold))
                            .foregroundStyle(BoardPalette.signal)
                    }
                    .padding(.bottom, 15)
                    Divider()
                        .overlay(BoardPalette.steel)
                        .padding(.bottom, 13)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("HELSINKI")
                                .font(.board(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(BoardPalette.fog)
                            Spacer()
                            Text("LIVE")
                                .font(.board(10, weight: .bold))
                                .tracking(0.8)
                                .foregroundStyle(BoardPalette.signal)
                        }
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "cloud.rain.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(BoardPalette.carbon)
                            .frame(width: 48, height: 48)
                            .background(BoardPalette.cyan, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("14 C")
                                    .font(.board(24, weight: .bold))
                                    .foregroundStyle(BoardPalette.mist)
                                Text("Light rain")
                                    .font(.board(11, weight: .semibold))
                                    .foregroundStyle(BoardPalette.fog)
                            }
                        }
                    }
                }
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Recent Codex work")
                        .font(.board(20, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Spacer()
                    MetricChip(value: "1", label: "active", tint: BoardPalette.signal)
                    MetricChip(value: "1", label: "waiting", tint: BoardPalette.amber)
                }
                taskRow(0, "Set up ESP32 Mac controller", "History available / eligible to continue", "IDLE", BoardPalette.fog)
                taskRow(1, "Package macOS companion", "Completed locally / tests passed", "DONE", BoardPalette.signal)
                taskRow(2, "Design work pulse UX", "Plan review needed on Mac", "REVIEW", BoardPalette.amber)
                Button {
                    onOpenXNews()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: xNewsEnabled ? "bolt.horizontal.fill" : "waveform.path.ecg")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BoardPalette.cyan)
                        Text(xNewsEnabled ? "X SIGNAL" : "WORK PULSE")
                            .font(.board(11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(BoardPalette.cyan)
                        Text(xNewsEnabled ? "AI agents move into desktop workflows" : "2 active / 3 recent Codex tasks")
                            .font(.board(13, weight: .semibold))
                            .foregroundStyle(BoardPalette.mist)
                            .lineLimit(1)
                        Spacer()
                        Text(xNewsEnabled ? "OPEN X NEWS" : "OPEN CODEX")
                            .font(.board(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(BoardPalette.fog)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BoardPalette.fog)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 45)
                    .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(xNewsEnabled ? "Open latest X News signal" : "Open Codex work pulse")
            }
        }
        .padding(.vertical, 4)
    }

    private var standaloneDashboard: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(title: "Board status")
                    Text("READY")
                        .font(.board(36, weight: .bold))
                        .foregroundStyle(BoardPalette.signal)
                        .padding(.top, 18)
                    Text("Dashboard runs locally")
                        .font(.board(16, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                        .padding(.top, 4)
                    Text("A Mac connection is optional")
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                        .padding(.top, 6)
                    Spacer()
                    SectionLabel(title: "Operating mode")
                    Text("LOCAL")
                        .font(.board(24, weight: .bold))
                        .foregroundStyle(BoardPalette.cyan)
                        .padding(.top, 6)
                    Text("No Mac required")
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                        .padding(.top, 2)
                    Divider()
                        .overlay(BoardPalette.steel)
                        .padding(.vertical, 14)
                    SectionLabel(title: "Helsinki · live")
                    HStack(spacing: 12) {
                        Image(systemName: "cloud.rain.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(BoardPalette.carbon)
                            .frame(width: 46, height: 46)
                            .background(BoardPalette.cyan, in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("14 C")
                                .font(.board(23, weight: .bold))
                                .foregroundStyle(BoardPalette.mist)
                            Text("Light rain")
                                .font(.board(11, weight: .semibold))
                                .foregroundStyle(BoardPalette.fog)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(width: 250)

            VStack(alignment: .leading, spacing: 12) {
                Text("Board at a glance")
                    .font(.board(20, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                localRow(
                    "Weather at a glance",
                    "Current conditions and the three-day forecast",
                    tint: BoardPalette.cyan,
                    action: onOpenWeather
                )
                localRow(
                    "Board settings",
                    "Wi-Fi, display, clock, units, focus and firmware update",
                    tint: BoardPalette.signal,
                    action: onOpenSettings
                )
                localRow(
                    "Focus cockpit",
                    "Hold a duration in Settings to begin a local session",
                    tint: BoardPalette.amber,
                    action: { onStartFocus(0) }
                )
                Button(action: xNewsEnabled ? onOpenXNews : onOpenWeather) {
                    HStack(spacing: 12) {
                        Image(systemName: xNewsEnabled ? "bolt.horizontal.fill" : "cloud.sun.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(BoardPalette.cyan)
                        Text(xNewsEnabled ? "X SIGNAL" : "WEATHER PULSE")
                            .font(.board(11, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(BoardPalette.cyan)
                        Text(xNewsEnabled ? "AI agents move into desktop workflows" : "Helsinki / 14 C / Light rain")
                            .font(.board(13, weight: .semibold))
                            .foregroundStyle(BoardPalette.mist)
                            .lineLimit(1)
                        Spacer()
                        Text(xNewsEnabled ? "OPEN X NEWS" : "OPEN WEATHER")
                            .font(.board(11, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(BoardPalette.fog)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(BoardPalette.fog)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 45)
                    .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func localRow(
        _ title: String,
        _ summary: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                StatusDot(color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.board(15, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text(summary)
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BoardPalette.fog)
            }
            .padding(.horizontal, 17)
            .frame(height: 76)
            .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func taskRow(
        _ index: Int,
        _ title: String,
        _ summary: String,
        _ status: String,
        _ tint: Color
    ) -> some View {
        Button {
            onOpenTask(index)
        } label: {
            HStack(spacing: 15) {
                StatusDot(color: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.board(15, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text(summary)
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                Text(status)
                    .font(.board(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(BoardPalette.fog)
            }
            .padding(.horizontal, 17)
            .frame(height: 76)
            .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Codex chat: \(title)")
        .onLongPressGesture(minimumDuration: 0.9) {
            onStartFocus(index)
        }
    }
}
