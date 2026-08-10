import Combine
import Foundation
import ServiceManagement

public enum LaunchAtLoginState: String, Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    public var title: String {
        switch self {
        case .disabled: "Off"
        case .enabled: "On"
        case .requiresApproval: "Needs approval"
        case .unavailable: "Install first"
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
private struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    var state: LaunchAtLoginState {
        let bundleURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let bundlePath = bundleURL.path + "/"
        let systemApplications = "/Applications/"
        let userApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .path + "/"
        guard bundleURL.pathExtension == "app",
              bundlePath.hasPrefix(systemApplications) || bundlePath.hasPrefix(userApplications) else {
            return .unavailable
        }

        return switch SMAppService.mainApp.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
public final class LaunchAtLoginController: ObservableObject {
    @Published public private(set) var state: LaunchAtLoginState
    @Published public private(set) var notice: String?

    private let service: LaunchAtLoginServicing

    public convenience init() {
        self.init(service: SystemLaunchAtLoginService())
    }

    init(service: LaunchAtLoginServicing) {
        self.service = service
        state = service.state
    }

    public func refresh() {
        let updatedState = service.state
        if updatedState != state {
            notice = nil
        }
        state = updatedState
    }

    public func enable() {
        notice = nil
        guard state == .disabled else { return }
        do {
            try service.register()
            refresh()
        } catch {
            refresh()
            notice = state == .requiresApproval
                ? "Approval is required in System Settings."
                : "Couldn’t enable launch at login. Install the signed app in Applications and try again."
        }
    }

    public func disable() {
        notice = nil
        guard state == .enabled || state == .requiresApproval else { return }
        do {
            try service.unregister()
            refresh()
        } catch {
            refresh()
            notice = "Couldn’t remove the Login Item. Review it in System Settings."
        }
    }

    public func openSystemSettings() {
        service.openSystemSettings()
    }
}
