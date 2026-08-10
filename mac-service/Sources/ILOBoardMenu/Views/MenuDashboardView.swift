import AppKit
import ILOBoardMenuSupport
import SwiftUI

struct MenuDashboardView: View {
    @ObservedObject var store: HostStatusStore
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @State private var diagnosticNotice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            details
            companionControls
            recentActivity
            Divider()
            diagnosticActions
            actions
        }
        .padding(18)
        .frame(width: 360)
        .onAppear { launchAtLogin.refresh() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: BrandImage.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("ILO Apps")
            VStack(alignment: .leading, spacing: 2) {
                Text("ILO Board")
                    .font(.headline)
                Text("Mac companion")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusChip
        }
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(store.state.tint)
                .frame(width: 7, height: 7)
            Text(store.state.chipTitle)
                .font(.caption2.weight(.bold))
                .tracking(0.6)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(store.state.tint.opacity(0.13), in: Capsule())
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: store.state.symbolName)
                .font(.title3)
                .foregroundStyle(store.state.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.state.title)
                    .font(.subheadline.weight(.semibold))
                Text(store.state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var details: some View {
        VStack(spacing: 9) {
            detailRow("Board", value: "Waveshare 5B · 1024×600")
            detailRow("Identity", value: shortBoardID)
            detailRow("Service", value: serviceDescription)
            detailRow("Last sync", value: lastSyncDescription)
            detailRow("Source", value: "Codex recent history")
            detailRow("Security", value: "TLS 1.2 · Read only")
        }
    }

    private var companionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Launch at login", systemImage: "power.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(launchAtLogin.state.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                switch launchAtLogin.state {
                case .disabled:
                    Button("Enable") { launchAtLogin.enable() }
                case .enabled:
                    Button("Disable") { launchAtLogin.disable() }
                case .requiresApproval:
                    Button("Review Login Items") { launchAtLogin.openSystemSettings() }
                    Button("Remove") { launchAtLogin.disable() }
                case .unavailable:
                    Text("Move the signed app to Applications to enable this.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let notice = launchAtLogin.notice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recent activity")
                .font(.caption.weight(.semibold))
            if store.connectionHistory.isEmpty {
                Text("No connection events yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.connectionHistory.prefix(3)) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(activityTint(entry.kind))
                            .frame(width: 6, height: 6)
                        Text(entry.kind.title)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.date.formatted(.relative(presentation: .named)))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption2)
                }
            }
        }
    }

    private var diagnosticActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Copy Diagnostics") {
                    DiagnosticExporter.copy(diagnosticSummary)
                    diagnosticNotice = "Privacy-safe diagnostics copied"
                }
                Button("Save…") {
                    DiagnosticExporter.save(diagnosticSummary) { saved in
                        diagnosticNotice = saved ? "Diagnostics saved" : nil
                    }
                }
                Spacer()
            }
            if let diagnosticNotice {
                Text(diagnosticNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var actions: some View {
        HStack {
            if store.state == .stopped || store.state == .notProvisioned || isFailure {
                Button("Start Service") { store.start() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Stop Service") { store.stop() }
            }
            Button("Copy Board ID") { store.copyBoardID() }
                .disabled(store.boardID == "—")
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit ILO Board")
        }
    }

    private var diagnosticSummary: String {
        store.diagnosticSummary(launchAtLogin: launchAtLogin.state)
    }

    private func activityTint(_ kind: ConnectionHistoryEntry.Kind) -> Color {
        switch kind {
        case .boardConnected: .green
        case .serviceIssue: .red
        case .waitingForBoard, .serviceStarting: .orange
        case .boardDisconnected, .serviceStopped, .setupRequired: .secondary
        }
    }

    private var shortBoardID: String {
        guard store.boardID.count > 24 else { return store.boardID }
        return "…" + store.boardID.suffix(20)
    }

    private var serviceDescription: String {
        store.servicePort.map { "Port \($0)" } ?? "Not listening"
    }

    private var lastSyncDescription: String {
        guard let lastSync = store.lastSync else { return "Not yet" }
        return lastSync.formatted(.relative(presentation: .named))
    }

    private var isFailure: Bool {
        if case .failed = store.state { return true }
        return false
    }
}
