import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var state: AppState
    var openTransferWindow: () -> Void
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.connectionStatus)
                .font(.headline)
            Toggle("剪贴板同步", isOn: $state.clipboardSyncEnabled)
            Text(state.latestClipboardStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text(state.transferSummary)
                .font(.caption)
            HStack {
                Button("打开传输窗口", action: openTransferWindow)
                Button("设置", action: openSettings)
                Button("退出") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
