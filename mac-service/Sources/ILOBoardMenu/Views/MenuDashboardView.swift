import AppKit
import BoardHostCore
import BoardProtocol
import ILOBoardMenuSupport
import SwiftUI

private enum CompanionDashboardSection: String, CaseIterable, Identifiable {
    case overview
    case features
    case activity

    var id: Self { self }

    func title(activityCount: Int) -> String {
        switch self {
        case .overview: "Overview"
        case .features: "Features"
        case .activity:
            activityCount == 0 ? "Activity" : "Activity \(min(activityCount, 99))"
        }
    }
}

struct MenuDashboardView: View {
    @ObservedObject var store: HostStatusStore
    @ObservedObject var weatherLocation: MacWeatherLocationController
    @ObservedObject var launchAtLogin: LaunchAtLoginController
    @ObservedObject var updater: SparkleUpdaterController
    @State private var diagnosticNotice: String?
    @State private var showingXNewsConsent = false
    @State private var showingCodexContinueConsent = false
    @State private var showingLocationConsent = false
    @State private var selectedSection = CompanionDashboardSection.overview

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                header
                sectionPicker
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            ScrollView {
                sectionContent
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
            }

            Divider()
            footer
        }
        .frame(width: 420, height: 580)
        .onAppear {
            launchAtLogin.refresh()
            weatherLocation.refresh()
            store.refreshXNewsStatus()
        }
        .confirmationDialog(
            "Enable board Continue action?",
            isPresented: $showingCodexContinueConsent,
            titleVisibility: .visible
        ) {
            Button("Enable Fixed Continue") { store.enableCodexContinue() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("After you hold and separately confirm on the paired board, it may resume one idle visible Codex task with exactly “Please continue.” It cannot approve commands, answer questions, or send other text.")
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
        .confirmationDialog(
            "Share Mac location for weather?",
            isPresented: $showingLocationConsent,
            titleVisibility: .visible
        ) {
            Button("Enable Coarse Location") { weatherLocation.enable() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ILO Board first rounds your location to about 1 km. macOS resolves that coarse point to a city or region, then the companion sends only the rounded coordinates and label over the encrypted paired connection. The board stores them so weather works without this Mac.")
        }
    }

    private var sectionPicker: some View {
        Picker("Dashboard section", selection: $selectedSection) {
            ForEach(CompanionDashboardSection.allCases) { section in
                Text(section.title(activityCount: store.connectionHistory.count))
                    .tag(section)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.small)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overview
        case .features:
            features
        case .activity:
            activity
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusCard
            if store.state == .pairingAuthorizationRequired {
                pairingAuthorizationCard
            } else {
                details
                quickControls
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 0) {
            firmwareUpdateControls
            Divider()
            companionControls
            Divider()
            codexContinueControls
            Divider()
            weatherLocationControls
            Divider()
            xNewsControls
        }
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .controlSize(.small)
    }

    private var activity: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(store.state.tint)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connection activity")
                        .font(.subheadline.weight(.semibold))
                    Text(activitySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            recentActivity
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: BrandImage.image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: store.state.symbolName)
                .font(.title3)
                .foregroundStyle(store.state.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.state.title)
                    .font(.subheadline.weight(.semibold))
                Text(store.connectionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(store.state == .connected ? store.state.tint : .secondary)
                .accessibilityLabel("Encrypted connection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var details: some View {
        VStack(spacing: 0) {
            detailRow("Board", value: "Waveshare 5B · 1024×600")
            Divider()
            detailRow("Identity", value: shortBoardID)
            Divider()
            detailRow("Service", value: serviceDescription)
            Divider()
            detailRow("USB", value: store.usbDescription)
            Divider()
            detailRow("Last sync", value: lastSyncDescription)
            Divider()
            detailRow("MacBook", value: macPowerDescription)
            Divider()
            detailRow("Source", value: "Codex recent history")
            Divider()
            detailRow("Security", value: store.securityDescription)
            Divider()
            detailRow("Mac companion", value: appReleaseInfo.displayVersion)
            Divider()
            detailRow("Firmware", value: store.firmwareVersion)
        }
    }

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Quick controls")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                launchAtLoginQuickControl
                Divider().padding(.leading, 38)
                codexContinueQuickControl
                Divider().padding(.leading, 38)
                navigationQuickControl(
                    title: "Weather location",
                    systemImage: "location",
                    status: weatherLocation.state.title,
                    tint: weatherLocationTint
                )
                Divider().padding(.leading, 38)
                navigationQuickControl(
                    title: "X News screen",
                    systemImage: "newspaper",
                    status: xNewsFetchStatusTitle,
                    tint: xNewsFetchStatusTint
                )
            }
            .padding(.horizontal, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private var launchAtLoginQuickControl: some View {
        HStack(spacing: 9) {
            quickControlIcon("power.circle")
            Text("Launch at login")
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            switch launchAtLogin.state {
            case .disabled, .enabled:
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            case .requiresApproval:
                Button("Review…") { launchAtLogin.openSystemSettings() }
                    .controlSize(.mini)
            case .unavailable:
                Text(launchAtLogin.state.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 34)
    }

    private var codexContinueQuickControl: some View {
        HStack(spacing: 9) {
            quickControlIcon("play.circle")
            Text("Codex Continue")
                .font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Text(store.codexContinueEnabled ? "Enabled" : "Off")
                .font(.caption2)
                .foregroundStyle(store.codexContinueEnabled ? .green : .secondary)
            Toggle("Codex Continue", isOn: codexContinueBinding)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .frame(minHeight: 34)
    }

    private func navigationQuickControl(
        title: String,
        systemImage: String,
        status: String,
        tint: Color
    ) -> some View {
        Button {
            selectedSection = .features
        } label: {
            HStack(spacing: 9) {
                quickControlIcon(systemImage)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 34)
        }
        .buttonStyle(.plain)
    }

    private func quickControlIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: 20)
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
                    if launchAtLogin.notice != nil {
                        Button("Review Login Items") { launchAtLogin.openSystemSettings() }
                    }
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
        .padding(.vertical, 10)
    }

    private var firmwareUpdateControls: some View {
        let status = store.firmwareUpdateStatus
        let presentation = HostStatusStore.firmwareUpdatePresentation(for: status.state)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Board firmware", systemImage: "arrow.triangle.2.circlepath.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(firmwareUpdateTitle(status, disabledTitle: presentation.title))
                    .font(.caption)
                    .foregroundStyle(firmwareUpdateTint(status.state))
            }
            if status.state == .downloading {
                ProgressView(value: Double(status.progressPercent), total: 100)
            }
            Text(status.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if status.state == .available {
                    Button("Install \(status.availableVersion ?? "update")") { store.installFirmwareUpdate() }
                        .buttonStyle(.borderedProminent)
                } else if [.idle, .upToDate, .failed].contains(status.state) {
                    Button("Check for Firmware Update") { store.checkForFirmwareUpdate() }
                }
                if status.state == .disabled {
                    Text(presentation.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func firmwareUpdateTitle(_ status: FirmwareUpdateStatusMessage, disabledTitle: String) -> String {
        switch status.state {
        case .disabled: disabledTitle
        case .idle: "Ready"
        case .checking: "Checking…"
        case .upToDate: "Up to date"
        case .available: status.availableVersion.map { "Version \($0)" } ?? "Available"
        case .downloading: "\(status.progressPercent)%"
        case .verifying: "Verifying…"
        case .rebooting: "Rebooting…"
        case .failed: "Try again"
        }
    }

    private func firmwareUpdateTint(_ state: FirmwareUpdateState) -> Color {
        switch state {
        case .available, .upToDate: .green
        case .failed: .orange
        default: .secondary
        }
    }

    private var xNewsControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("X News screen", systemImage: "newspaper")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(xNewsFetchStatusTitle)
                    .font(.caption)
                    .foregroundStyle(xNewsFetchStatusTint)
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
                    Button {
                        store.refreshXNewsNow()
                    } label: {
                        if xNewsIsFetching {
                            HStack(spacing: 5) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Fetching…")
                            }
                        } else {
                            Label(xNewsRefreshButtonTitle, systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(xNewsRefreshIsDisabled)
                    Spacer()
                    Text(xNewsCacheDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
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
        .padding(.vertical, 10)
    }

    private var codexContinueControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Codex Continue", systemImage: "play.circle")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(store.codexContinueEnabled ? "Enabled" : "Off")
                    .font(.caption)
                    .foregroundStyle(store.codexContinueEnabled ? .green : .secondary)
            }
            Text("Allows only the fixed “Please continue.” message for an idle visible task after hold plus separate confirmation on the board.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.codexContinueEnabled {
                Button("Disable") { store.disableCodexContinue() }
            } else {
                Button("Enable Fixed Continue…") { showingCodexContinueConsent = true }
            }
        }
        .padding(.vertical, 10)
    }

    private var weatherLocationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weather location", systemImage: "location")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(weatherLocation.state.title)
                    .font(.caption)
                    .foregroundStyle(weatherLocationTint)
            }
            Text(weatherLocation.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            switch weatherLocation.state {
            case .off:
                Button("Use This Mac’s Location…") { showingLocationConsent = true }
            case .permissionRequired:
                HStack {
                    Button("Request Permission") { weatherLocation.enable() }
                    Button("Stop Sharing") { weatherLocation.disable() }
                }
            case .denied:
                HStack {
                    Button("Open Location Settings…") { weatherLocation.openLocationSettings() }
                    Button("Stop Sharing") { weatherLocation.disable() }
                }
            case .unavailable:
                HStack {
                    Button("Open Location Settings…") { weatherLocation.openLocationSettings() }
                    Button("Try Again") { weatherLocation.enable() }
                    Button("Stop Sharing") { weatherLocation.disable() }
                }
            case .requesting, .ready:
                Button("Stop Sharing") { weatherLocation.disable() }
            }
        }
        .padding(.vertical, 10)
    }

    private var weatherLocationTint: Color {
        switch weatherLocation.state {
        case .ready: .green
        case .permissionRequired, .denied, .unavailable: .orange
        case .off, .requesting: .secondary
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.state == .enabled },
            set: { enabled in
                if enabled {
                    launchAtLogin.enable()
                } else {
                    launchAtLogin.disable()
                }
            }
        )
    }

    private var codexContinueBinding: Binding<Bool> {
        Binding(
            get: { store.codexContinueEnabled },
            set: { enabled in
                if enabled {
                    showingCodexContinueConsent = true
                } else {
                    store.disableCodexContinue()
                }
            }
        )
    }

    private var xNewsCadenceBinding: Binding<XNewsRefreshCadence> {
        Binding(
            get: { store.xNewsStatus.cadence },
            set: { store.enableXNews(cadence: $0) }
        )
    }

    private var xNewsFetchStatusTitle: String {
        guard store.xNewsStatus.grokAvailable else { return "Unavailable" }
        guard store.xNewsStatus.isEnabled else { return "Off" }
        if xNewsCooldownUntil != nil, case .idle = store.xNewsRefreshActivity { return "Cooldown" }
        return switch store.xNewsRefreshActivity {
        case .idle: "Ready"
        case .fetching: "Fetching"
        case .updated: "Updated"
        case .disabled: "Off"
        case .cooldown: "Cooldown"
        case .failed: "Needs attention"
        }
    }

    private var xNewsFetchStatusTint: Color {
        switch store.xNewsRefreshActivity {
        case .failed: .orange
        case .fetching, .updated: .green
        case .idle, .disabled, .cooldown: store.xNewsStatus.isEnabled ? .green : .secondary
        }
    }

    private var xNewsIsFetching: Bool {
        if case .fetching = store.xNewsRefreshActivity { return true }
        return false
    }

    private var xNewsRefreshIsDisabled: Bool {
        if xNewsIsFetching { return true }
        if xNewsCooldownUntil != nil { return true }
        return !store.xNewsStatus.isEnabled
    }

    private var xNewsRefreshButtonTitle: String {
        if let until = xNewsCooldownUntil {
            let minutes = max(1, Int(ceil(until.timeIntervalSinceNow / 60)))
            return "Refresh in \(minutes)m"
        }
        return "Refresh now"
    }

    private var xNewsCooldownUntil: Date? {
        let until: Date?
        if case let .cooldown(activityUntil) = store.xNewsRefreshActivity {
            until = activityUntil
        } else if let lastAttempt = store.xNewsStatus.lastAttemptAt {
            until = lastAttempt.addingTimeInterval(XNewsRefreshPolicy.manualCooldown)
        } else {
            until = nil
        }
        guard let until, until > Date() else { return nil }
        return until
    }

    private var xNewsCacheDescription: String {
        guard let generatedAt = store.xNewsCacheGeneratedAt, store.xNewsCachedStoryCount > 0 else {
            return "No verified cache"
        }
        return "\(store.xNewsCachedStoryCount) stories · \(generatedAt.formatted(.relative(presentation: .named)))"
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
        VStack(alignment: .leading, spacing: 0) {
            if store.connectionHistory.isEmpty {
                Text("No connection events yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(store.connectionHistory) { entry in
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
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 34)
                    Divider().padding(.leading, 26)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let diagnosticNotice {
                Text(diagnosticNotice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Button {
                    DiagnosticExporter.copy(diagnosticSummary)
                    diagnosticNotice = "Privacy-safe diagnostics copied"
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                }

                Button {
                    DiagnosticExporter.save(diagnosticSummary) { saved in
                        diagnosticNotice = saved ? "Diagnostics saved" : nil
                    }
                } label: {
                    Label("Save…", systemImage: "square.and.arrow.down")
                }

                Spacer()

                Menu {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.isAvailable)

                    Divider()

                    if store.state == .stopped || store.state == .notProvisioned || isFailure {
                        Button("Start Service") { store.start() }
                    } else if store.state != .pairingAuthorizationRequired {
                        Button("Stop Service") { store.stop() }
                    }

                    Button("Copy Board ID") { store.copyBoardID() }
                        .disabled(store.boardID == "—")

                    Divider()

                    Button("Quit ILO Board") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("More actions")
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
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
        .padding(.vertical, 3)
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

    private var activitySummary: String {
        guard let latest = store.connectionHistory.first else {
            return "Connection events will appear here as the service runs."
        }
        return "\(latest.kind.title) · \(latest.date.formatted(.relative(presentation: .named)))"
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
