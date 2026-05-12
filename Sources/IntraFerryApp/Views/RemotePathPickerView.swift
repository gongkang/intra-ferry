import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Remote path", text: $state.remotePath)
                Button("Refresh") {
                    Task {
                        await state.refreshRemotePath()
                    }
                }
            }
            if state.remoteEntries.isEmpty {
                Text("No remote entries. Configure an authorized receive location on the peer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(state.remoteEntries) { entry in
                    Button(entry.isDirectory ? "\(entry.name)/" : entry.name) {
                        if entry.isDirectory {
                            state.remotePath = entry.path
                        }
                    }
                }
                .frame(height: 120)
            }
        }
    }
}
