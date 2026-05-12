import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        Form {
            TextField("Local name", text: $state.localName)
            TextField("Peer host", text: $state.peerHost)
            TextField("Peer port", value: $state.peerPort, format: .number)
            SecureField("Shared token", text: $state.sharedToken)
            TextField("Authorized receive path", text: $state.authorizedReceivePath)
            Toggle("Enable clipboard sync by default", isOn: $state.clipboardSyncEnabled)
            Button("Save") {
                state.saveSettings()
            }
        }
        .padding()
        .frame(width: 460)
    }
}
