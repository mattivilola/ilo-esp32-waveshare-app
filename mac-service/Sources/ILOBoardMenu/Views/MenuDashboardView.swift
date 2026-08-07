import AppKit
import SwiftUI

struct MenuDashboardView: View {
    @ObservedObject var store: HostStatusStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusCard
            details
            Divider()
            actions
        }
        .padding(18)
        .frame(width: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            detailRow("Security", value: "TLS 1.2 · Read only")
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
