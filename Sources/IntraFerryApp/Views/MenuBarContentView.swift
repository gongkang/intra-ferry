import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var state: AppState
    var openTransferWindow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.connectionStatus)
                .font(.headline)
            Toggle("Clipboard Sync", isOn: $state.clipboardSyncEnabled)
            Text(state.latestClipboardStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(state.transferSummary)
                .font(.caption)
            HStack {
                Button("Open Transfer Window", action: openTransferWindow)
                Button("Settings") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
