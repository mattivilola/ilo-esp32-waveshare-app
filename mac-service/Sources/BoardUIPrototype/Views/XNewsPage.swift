import SwiftUI

struct XNewsPage: View {
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI + humanoid robotics")
                        .font(.board(20, weight: .semibold))
                        .foregroundStyle(BoardPalette.mist)
                    Text("Rolling 24 hours · refreshed by the Mac companion")
                        .font(.board(11))
                        .foregroundStyle(BoardPalette.fog)
                }
                Spacer()
                verificationChip("3 CITED STORIES", tint: BoardPalette.signal)
                verificationChip("08:00", tint: BoardPalette.cyan)
            }

            HStack(spacing: 14) {
                featuredStory
                    .frame(width: 430)
                VStack(spacing: 12) {
                    compactStory(
                        category: "ROBOTICS",
                        title: "Humanoid pilot moves from demo to measured factory trial",
                        source: "@primary_source · 43 min",
                        tint: BoardPalette.cyan
                    )
                    compactStory(
                        category: "AI",
                        title: "New multimodal model targets real-time physical control",
                        source: "@research_lab · 2 hr",
                        tint: BoardPalette.signal
                    )
                }
            }

            HStack(spacing: 8) {
                StatusDot(color: BoardPalette.signal)
                Text("DIRECT X POSTS · TIMESTAMPS CHECKED LOCALLY")
                    .font(.board(10, weight: .bold))
                    .tracking(0.65)
                    .foregroundStyle(BoardPalette.fog)
                Spacer()
                Text("SAMPLE CONTRACT · GROK VIA MAC")
                    .font(.board(10, weight: .bold))
                    .tracking(0.65)
                    .foregroundStyle(BoardPalette.amber)
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
    }

    private var featuredStory: some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    verificationChip("AI · HIGH", tint: BoardPalette.signal)
                    Spacer()
                    Text("18 MIN")
                        .font(.board(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(BoardPalette.fog)
                }
                Text("Open model release improves compact on-device reasoning")
                    .font(.board(22, weight: .bold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The primary-source post includes release details and measured results. The board receives only this bounded summary and its verified citation.")
                    .font(.board(12))
                    .foregroundStyle(BoardPalette.fog)
                    .lineSpacing(4)
                    .lineLimit(3)
                Spacer()
                Divider().overlay(BoardPalette.steel)
                HStack {
                    Text("@model_lab")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(BoardPalette.cyan)
                    Spacer()
                    Text("1 DIRECT POST")
                        .font(.board(10, weight: .bold))
                        .tracking(0.65)
                        .foregroundStyle(BoardPalette.signal)
                }
            }
        }
    }

    private func compactStory(category: String, title: String, source: String, tint: Color) -> some View {
        PulseCard {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(category)
                        .font(.board(10, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(tint)
                    Spacer()
                    Text("VERIFIED")
                        .font(.board(9, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(BoardPalette.signal)
                }
                Text(title)
                    .font(.board(15, weight: .semibold))
                    .foregroundStyle(BoardPalette.mist)
                    .lineLimit(2)
                Spacer()
                Text(source)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(BoardPalette.fog)
            }
        }
    }

    private func verificationChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.board(10, weight: .bold))
            .tracking(0.65)
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.11), in: Capsule())
    }
}
