import AppKit
import SwiftUI

final class ILOBoardAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct ILOBoardMenuApp: App {
    @NSApplicationDelegateAdaptor(ILOBoardAppDelegate.self) private var appDelegate
    @StateObject private var store = HostStatusStore()

    var body: some Scene {
        MenuBarExtra {
            MenuDashboardView(store: store)
        } label: {
            Label("ILO Board", systemImage: store.state.symbolName)
        }
        .menuBarExtraStyle(.window)
    }
}
