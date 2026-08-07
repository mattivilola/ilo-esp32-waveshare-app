import SwiftUI

enum HostServiceState: Equatable {
    case notProvisioned
    case starting
    case listening
    case connected
    case stopped
    case failed(String)

    var title: String {
        switch self {
        case .notProvisioned: "Not provisioned"
        case .starting: "Starting"
        case .listening: "Waiting for board"
        case .connected: "Board connected"
        case .stopped: "Service stopped"
        case .failed: "Needs attention"
        }
    }

    var detail: String {
        switch self {
        case .notProvisioned: "Run ./tools/board provision"
        case .starting: "Opening encrypted local service"
        case .listening: "The Mac is ready on your network"
        case .connected: "Encrypted status sync is active"
        case .stopped: "The board will retain its last snapshot"
        case let .failed(message): message
        }
    }

    var symbolName: String {
        switch self {
        case .connected: "rectangle.connected.to.line.below"
        case .listening, .starting: "antenna.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        case .notProvisioned, .stopped: "rectangle.slash"
        }
    }

    var chipTitle: String {
        switch self {
        case .connected: "ONLINE"
        case .listening: "READY"
        case .starting: "STARTING"
        case .failed: "ISSUE"
        case .notProvisioned: "SETUP"
        case .stopped: "OFFLINE"
        }
    }

    var tint: Color {
        switch self {
        case .connected: .green
        case .listening, .starting: .orange
        case .failed: .red
        case .notProvisioned, .stopped: .secondary
        }
    }
}
