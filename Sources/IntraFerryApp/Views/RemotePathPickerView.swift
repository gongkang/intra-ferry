import SwiftUI

struct RemotePathPickerView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            Divider()
            browserContent
        }
        .background(Color(nsColor: .textBackgroundColor))
        .task {
            if state.remotePath.isEmpty && state.remoteBrowsePath.isEmpty {
                await state.refreshRemotePath()
            }
        }
    }

    private var pathBar: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.browseRemoteParent() }
            } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.bordered)
            .help("上一级")

            TextField("远端路径", text: $state.remoteBrowsePath)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task { await state.refreshRemotePath() }
                }

            Button {
                Task { await state.refreshRemotePath() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .help("刷新")

            Button("设为目标") {
                state.selectRemoteBrowsePath()
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.remoteBrowsePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    @ViewBuilder
    private var browserContent: some View {
        if state.remoteBrowserStatus.hasPrefix("浏览失败") || state.remoteEntries.isEmpty {
            emptyState
        } else {
            directoryList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(state.remoteBrowserStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyStateIcon: String {
        if state.remoteBrowserStatus.hasPrefix("浏览失败") {
            return "exclamationmark.triangle"
        }
        return "folder"
    }

    private var directoryList: some View {
        List(state.remoteEntries) { entry in
            Button {
                if entry.isDirectory {
                    Task { await state.enterRemoteDirectory(entry) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc")
                        .foregroundStyle(entry.isDirectory ? .blue : .secondary)
                    Text(entry.isDirectory ? "\(entry.name)/" : entry.name)
                        .lineLimit(1)
                    Spacer()
                    if entry.path == state.trimmedRemoteSendTarget {
                        Text("目标")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    if entry.isDirectory {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.isDirectory)
        }
        .listStyle(.inset)
    }
}
