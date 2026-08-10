import AppKit
import ILOBoardMenuSupport
import SwiftUI

final class ILOBoardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = BrandImage.image
    }
}

@main
struct ILOBoardMenuApp: App {
    @NSApplicationDelegateAdaptor(ILOBoardAppDelegate.self) private var appDelegate
    @StateObject private var store = HostStatusStore()
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some Scene {
        MenuBarExtra {
            MenuDashboardView(store: store, launchAtLogin: launchAtLogin)
        } label: {
            Label("ILO Board", systemImage: store.state.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
