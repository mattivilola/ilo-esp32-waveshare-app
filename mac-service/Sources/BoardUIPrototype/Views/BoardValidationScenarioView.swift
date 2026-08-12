import SwiftUI

struct BoardValidationScenarioView: View {
    let scenario: BoardPreviewScenario

    var body: some View {
        switch scenario {
        case .offline:
            dashboardState(
                eyebrow: "CONNECTION LOST",
                headline: "Mac unavailable",
                detail: "Last successful sync 4 min ago",
                tint: BoardPalette.amber,
                rows: [
                    ("Codex", "Cached summaries · 4 min old", "STALE"),
                    ("Weather", "Direct connection remains available", "LIVE"),
                    ("Recovery", "Trying the known Mac address", "RETRYING")
                ]
            )
        case .loading:
            codexState(
                title: "Loading recent Codex tasks",
                detail: "The Mac companion is preparing a privacy-safe snapshot.",
                tint: BoardPalette.cyan,
                rows: [
                    ("Fetching task list", "Waiting for local App Server"),
                    ("Sanitizing fields", "Prompts, paths and transcripts stay on Mac"),
                    ("Preparing board view", "No action is required")
                ]
            )
        case .stale:
            weatherState(
                badge: "STALE · 47 MIN",
                headline: "14°C",
                condition: "Last known: light rain",
                detail: "Showing the latest verified cache while the board retries.",
                tint: BoardPalette.amber
            )
        case .error:
            weatherState(
                badge: "OFFLINE",
                headline: "Weather unavailable",
                condition: "No verified forecast to show",
                detail: "Check Wi-Fi in Settings. The board will retry automatically.",
                tint: BoardPalette.amber
            )
        case .longText:
            codexState(
                title: "Long-content boundary",
                detail: "Rows stay inside their cards and truncate instead of changing touch geometry.",
                tint: BoardPalette.signal,
                rows: [
                    ("Investigate the production reconciliation workflow without exposing private customer details or local workspace paths", "History available · live Desktop state unavailable"),
                    ("Build and verify an intentionally overlong task name for the fixed-width board layout", "Summary is constrained to one readable line"),
                    ("Short task", "Normal rows remain visually balanced")
                ]
            )
        case .privacy:
            dashboardState(
                eyebrow: "PRIVACY MODE",
                headline: "Summaries hidden",
                detail: "Counts and coarse state remain visible",
                tint: BoardPalette.signal,
                rows: [
                    ("Active task", "Hidden on this board", "ACTIVE"),
                    ("Waiting task", "Hidden on this board", "WAITING"),
                    ("Recent history", "Hidden on this board", "PRIVATE")
                ]
            )
        case .reconnect:
            dashboardState(
                eyebrow: "RECONNECTING",
                headline: "Finding your Mac",
                detail: "Attempt 2 · retrying in 4 seconds",
                tint: BoardPalette.cyan,
                rows: [
                    ("Wi-Fi", "Known network connected", "READY"),
                    ("Mac companion", "Authenticated session interrupted", "RETRYING"),
                    ("Board data", "Last snapshot kept read only", "CACHED")
                ]
            )
        case .approvalRequest:
            approvalRequest
        case .sleep, .screensaver:
            EmptyView()
        }
    }

    private var approvalRequest: some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Approval request · fixture")
                    Text("Allow one planned build?")
                        .font(.board(26, weight: .bold))
                        .foregroundStyle(BoardPalette.mist)
                    Text("Consequence")
                        .font(.board(11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(BoardPalette.amber)
                    Text("Would allow one local make verify run on the paired Mac.")
                        .font(.board(15, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                        .lineSpacing(4)
                    Spacer()
                    HStack {
                        Text("EXPIRES IN 01:42")
                        Spacer()
                        Text("REQUEST 7A2F")
                    }
                    .font(.board(11, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(BoardPalette.fog)
                }
            }

            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Two explicit steps")
                    Text("HOLD 1.5 SEC")
                        .font(.board(24, weight: .bold))
                        .foregroundStyle(BoardPalette.amber)
                    Text("Then review the same consequence and tap Confirm. A tap or interrupted hold does nothing.")
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.fog)
                        .lineSpacing(4)
                    Text("HOLD TO CONTINUE")
                        .font(.board(13, weight: .bold))
                        .tracking(0.9)
                        .foregroundStyle(BoardPalette.mist)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(BoardPalette.amber.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                        .overlay {
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(BoardPalette.amber, lineWidth: 1)
                        }
                    Spacer()
                    Text("NOT CONNECTED · NO ACTION SENT")
                        .font(.board(11, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(BoardPalette.amber)
                    Text("Expiry, one-time request IDs and Mac audit are required before transport is enabled.")
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                }
            }
            .frame(width: 390)
        }
        .padding(.vertical, 4)
    }

    private func dashboardState(
        eyebrow: String,
        headline: String,
        detail: String,
        tint: Color,
        rows: [(String, String, String)]
    ) -> some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: eyebrow)
                    Text(headline)
                        .font(.board(30, weight: .bold))
                        .foregroundStyle(tint)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.fog)
                        .lineSpacing(3)
                    Spacer()
                    Text("VALIDATION FIXTURE")
                        .font(.board(10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(BoardPalette.fog)
                }
            }
            .frame(width: 300)

            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    stateRow(title: row.0, detail: row.1, badge: row.2, tint: tint)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func codexState(
        title: String,
        detail: String,
        tint: Color,
        rows: [(String, String)]
    ) -> some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.board(20, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text(detail)
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                Text("VALIDATION FIXTURE")
                    .font(.board(10, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(tint)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                stateRow(
                    title: row.0,
                    detail: row.1,
                    badge: scenario == .loading ? (index == 0 ? "LOADING" : "QUEUED") : "CONSTRAINED",
                    tint: tint
                )
            }
        }
        .padding(.vertical, 4)
    }

    private func weatherState(
        badge: String,
        headline: String,
        condition: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 16) {
            PulseCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(title: "Helsinki")
                    Text(headline)
                        .font(.board(headline.count > 8 ? 32 : 70, weight: .bold))
                        .foregroundStyle(BoardPalette.mist)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(condition)
                        .font(.board(17, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(.board(13))
                        .foregroundStyle(BoardPalette.fog)
                        .lineSpacing(4)
                    Spacer()
                    Text("Weather data by Open-Meteo.com")
                        .font(.board(11, weight: .semibold))
                        .foregroundStyle(BoardPalette.fog)
                }
            }
            .frame(width: 500)

            PulseCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(badge)
                        .font(.board(13, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.12), in: Capsule())
                    Text("No cached result is ever presented as current.")
                        .font(.board(18, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                        .lineSpacing(4)
                    Spacer()
                    Text("Automatic retry · no action on transient errors")
                        .font(.board(12))
                        .foregroundStyle(BoardPalette.fog)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stateRow(title: String, detail: String, badge: String, tint: Color) -> some View {
        HStack(spacing: 15) {
            StatusDot(color: tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.board(15, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(detail)
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            Text(badge)
                .font(.board(10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(tint)
                .fixedSize()
        }
        .padding(.horizontal, 17)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BoardPalette.slate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A black fixture intentionally represents the expected visible result of a
/// binary backlight-off state. Actual CH422G behavior still requires hardware.
struct BoardSleepValidationView: View {
    var body: some View {
        Color.black
            .frame(width: 1024, height: 600)
            .accessibilityLabel("Simulated display asleep; physical backlight behavior is unverified")
    }
}

struct BoardScreensaverValidationView: View {
    var body: some View {
        ZStack {
            BoardPalette.carbon
            HStack(spacing: 20) {
                Image(nsImage: BrandAsset.image())
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text("ILO / PULSE")
                        .font(.board(18, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(BoardPalette.signal)
                    Text("09:41")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(BoardPalette.mist)
                    Text("SUN 10 AUG · EEST")
                        .font(.board(14, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(BoardPalette.fog)
                    HStack(spacing: 9) {
                        Circle()
                            .fill(BoardPalette.signal)
                            .frame(width: 8, height: 8)
                        Text("Touch to wake")
                            .font(.board(13))
                            .foregroundStyle(BoardPalette.fog)
                    }
                    .padding(.top, 5)
                }
            }
            .offset(x: 126, y: -82)
        }
        .frame(width: 1024, height: 600)
        .accessibilityLabel("Pulse screensaver fixture showing clock, date, and timezone")
    }
}
