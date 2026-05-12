import AppKit
import SwiftUI
import IntraFerryCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState(environment: AppEnvironment.production())

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var transferWindow: NSWindow?
    private var settingsWindow: NSWindow?

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

        NSApp.activate(ignoringOtherApps: true)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(state: state, openTransferWindow: { [weak self] in
                self?.showTransferWindow()
            }, openSettings: { [weak self] in
                self?.showSettingsWindow()
            })
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        bringPopoverToFront(popover)
        self.popover = popover
    }

    private func bringPopoverToFront(_ popover: NSPopover) {
        guard let window = popover.contentViewController?.view.window else {
            Task { @MainActor [weak self, weak popover] in
                guard let self, let popover else {
                    return
                }
                self.bringPopoverToFront(popover)
            }
            return
        }

        window.level = .statusBar
        window.collectionBehavior.insert(.transient)
        window.orderFrontRegardless()
    }

    private func showTransferWindow() {
        popover?.performClose(nil)
        if let transferWindow {
            NSApp.activate(ignoringOtherApps: true)
            transferWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Ferry 传输"
        window.contentViewController = NSHostingController(rootView: TransferWindowView(state: state))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        transferWindow = window
    }

    private func showSettingsWindow() {
        popover?.performClose(nil)
        if let settingsWindow {
            NSApp.activate(ignoringOtherApps: true)
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Ferry 设置"
        window.contentViewController = NSHostingController(rootView: SettingsView(state: state))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }

        if window === settingsWindow {
            settingsWindow = nil
        } else if window === transferWindow {
            transferWindow = nil
        }
    }
}
