import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("发送目标：\(state.remotePath.isEmpty ? "未选择" : state.remotePath)")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("浏览路径", text: $state.remoteBrowsePath)
                Button {
                    Task {
                        await state.browseRemoteParent()
                    }
                } label: {
                    Label("上一级", systemImage: "arrow.up")
                }
                Button {
                    Task {
                        await state.refreshRemotePath()
                    }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                Button {
                    state.selectRemoteBrowsePath()
                } label: {
                    Label("选择当前路径", systemImage: "checkmark.circle")
                }
            }
            Text(state.remoteBrowserStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if state.remoteEntries.isEmpty {
                Text("暂无目录内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List(state.remoteEntries) { entry in
                    Button {
                        if entry.isDirectory {
                            Task {
                                await state.enterRemoteDirectory(entry)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                            Text(entry.isDirectory ? "\(entry.name)/" : entry.name)
                            Spacer()
                            if entry.isDirectory {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!entry.isDirectory)
                }
                .frame(height: 170)
            }
        }
        .task {
            if state.remotePath.isEmpty && state.remoteBrowsePath.isEmpty {
                await state.refreshRemotePath()
            }
        }
    }
}
