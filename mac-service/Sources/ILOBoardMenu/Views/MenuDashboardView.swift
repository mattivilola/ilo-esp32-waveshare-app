import AppKit
import BoardHostCore
import ILOBoardMenuSupport
import SwiftUI

struct MenuDashboardView: View {
    @ObservedObject var store: HostStatusStore
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @ObservedObject var updater: SparkleUpdaterController
    @State private var diagnosticNotice: String?
    @State private var showingXNewsConsent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            if store.state == .pairingAuthorizationRequired {
                pairingAuthorizationCard
            } else {
                details
                companionControls
                xNewsControls
                recentActivity
            }
            Divider()
            diagnosticActions
            actions
        }
        .padding(18)
        .frame(width: 360)
        .onAppear {
            launchAtLogin.refresh()
            store.refreshXNewsStatus()
        }
        .confirmationDialog(
            "Enable X News?",
            isPresented: $showingXNewsConsent,
            titleVisibility: .visible
        ) {
            Button("Enable Daily X News") { store.enableXNews() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This runs your authenticated Grok CLI with X search and may use paid model or tool capacity. Credentials remain on this Mac.")
        }
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
            detailRow("MacBook", value: macPowerDescription)
            detailRow("Source", value: "Codex recent history")
            detailRow("Security", value: "TLS 1.2 · Read only")
            detailRow("App", value: appReleaseInfo.displayVersion)
        }
    }

    @ViewBuilder
    private var pairingAuthorizationCard: some View {
        if store.state == .pairingAuthorizationRequired {
            VStack(alignment: .leading, spacing: 9) {
                Label("One-time secure pairing access", systemImage: "lock.shield.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("USB setup saved this board’s encrypted pairing key in your Mac login Keychain. ILO Board needs your approval once to copy it into an app-owned Keychain item for future launches.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("After you continue, macOS will ask for your Mac login password. Click Allow. The pairing key is never displayed or uploaded.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Continue & Authorize…") { store.authorizeSecurePairing() }
                    .buttonStyle(.borderedProminent)
                if let notice = store.pairingAuthorizationNotice {
                    Text(notice)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.blue.opacity(0.25), lineWidth: 1)
            }
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

    private var xNewsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("X News screen", systemImage: "newspaper")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(xNewsStatusTitle)
                    .font(.caption)
                    .foregroundStyle(store.xNewsStatus.isEnabled ? .green : .secondary)
            }

            Text(xNewsStatusDetail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !store.xNewsStatus.grokAvailable {
                Text("Install and authenticate the Grok CLI to make this screen available.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            } else if store.xNewsStatus.isEnabled {
                HStack(spacing: 8) {
                    Picker("Schedule", selection: xNewsCadenceBinding) {
                        Text("Daily").tag(XNewsRefreshCadence.daily)
                        Text("2× daily").tag(XNewsRefreshCadence.morningAndAfternoon)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Button("Disable") { store.disableXNews() }
                }
            } else {
                Button("Enable X News…") { showingXNewsConsent = true }
            }

            if let notice = store.xNewsNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var xNewsCadenceBinding: Binding<XNewsRefreshCadence> {
        Binding(
            get: { store.xNewsStatus.cadence },
            set: { store.enableXNews(cadence: $0) }
        )
    }

    private var xNewsStatusTitle: String {
        guard store.xNewsStatus.grokAvailable else { return "Unavailable" }
        return switch store.xNewsStatus.cadence {
        case .off: "Off"
        case .daily: "Daily"
        case .morningAndAfternoon: "Twice daily"
        }
    }

    private var xNewsStatusDetail: String {
        guard store.xNewsStatus.grokAvailable else { return "Hidden on the board because Grok was not found." }
        return switch store.xNewsStatus.cadence {
        case .off: "Off by default; the X News screen is hidden on the board."
        case .daily: "Visible on the board; refreshes at 08:00 local time."
        case .morningAndAfternoon: "Visible on the board; refreshes at 08:00 and 14:00 local time."
        }
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
        VStack(spacing: 10) {
            HStack {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isAvailable)
                Spacer()
                Text(updater.isAvailable ? "Signed update feed ready" : "Updates available in signed builds")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack {
                if store.state == .stopped || store.state == .notProvisioned || isFailure {
                    Button("Start Service") { store.start() }
                        .buttonStyle(.borderedProminent)
                } else if store.state != .pairingAuthorizationRequired {
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
    }

    private var appReleaseInfo: AppReleaseInfo {
        AppReleaseInfo(infoDictionary: Bundle.main.infoDictionary)
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

    private var macPowerDescription: String {
        guard let power = store.macPowerStatus else { return "Battery unavailable" }
        let state: String
        switch power.state {
        case .battery: state = "On battery"
        case .charging: state = "Charging"
        case .powerAdapter: state = "Power adapter"
        case .full: state = "Fully charged"
        }
        return "\(power.levelPercent)% · \(state)"
    }

    private var isFailure: Bool {
        if case .failed = store.state { return true }
        return false
    }
}
