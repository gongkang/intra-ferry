import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("对端路径", text: $state.remotePath)
                Button("刷新") {
                    Task {
                        await state.refreshRemotePath()
                    }
                }
            }
            if state.remoteEntries.isEmpty {
                Text("暂无对端目录内容。请先在对端配置允许接收路径。")
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
