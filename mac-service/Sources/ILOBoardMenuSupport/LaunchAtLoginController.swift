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

enum LaunchAtLoginSystemStatus: Equatable, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

extension LaunchAtLoginState {
    static func resolve(isInstalledApplication: Bool, systemStatus: LaunchAtLoginSystemStatus) -> Self {
        guard isInstalledApplication else { return .unavailable }
        return switch systemStatus {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        // On a first run, backgroundtaskmanagementd can report no record for
        // SMAppService.mainApp. The explicit register() call creates that record;
        // treating it as an installation failure makes registration impossible.
        case .notFound: .disabled
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
        let isInstalledApplication = bundleURL.pathExtension == "app"
            && (bundlePath.hasPrefix(systemApplications) || bundlePath.hasPrefix(userApplications))
        let systemStatus: LaunchAtLoginSystemStatus = switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
        return .resolve(isInstalledApplication: isInstalledApplication, systemStatus: systemStatus)
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
            notice = switch state {
            case .requiresApproval:
                "ILO Board is registered, but approval is required in Login Items."
            case .unavailable:
                "Launch at login is available only from the signed app in Applications."
            case .disabled, .enabled:
                "macOS couldn’t register ILO Board. Review Login Items and try again."
            }
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
