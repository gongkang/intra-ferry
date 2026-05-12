import AppKit
import SwiftUI
import IntraFerryCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(environment: AppEnvironment.production())

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.loadAndStartServices()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Ferry"
        statusItem = item
    }
}
