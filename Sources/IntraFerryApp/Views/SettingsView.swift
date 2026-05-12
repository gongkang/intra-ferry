import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            TextField("本机名称", text: $state.localName)
            TextField("对端地址", text: $state.peerHost)
            TextField("对端端口", text: $state.peerPortText)
            SecureField("共享口令", text: $state.sharedToken)
            TextField("允许接收路径", text: $state.authorizedReceivePath)
            Toggle("默认启用剪贴板同步", isOn: $state.clipboardSyncEnabled)
            HStack {
                Button("保存") {
                    state.saveSettings()
                }
                Text(state.settingsStatus)
                    .font(.caption)
                    .foregroundStyle(state.settingsStatusIsError ? .red : .secondary)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
