import AppKit
import SwiftUI
import IntraFerryCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(environment: AppEnvironment.production())

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var transferWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.loadAndStartServices()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Ferry"
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else {
            return
        }

        if popover?.isShown == true {
            popover?.performClose(nil)
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(state: state, openTransferWindow: { [weak self] in
                self?.showTransferWindow()
            })
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }

    private func showTransferWindow() {
        if let transferWindow {
            transferWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intra Ferry Transfer"
        window.contentViewController = NSHostingController(rootView: TransferWindowView(state: state))
        window.center()
        window.makeKeyAndOrderFront(nil)
        transferWindow = window
    }
}
