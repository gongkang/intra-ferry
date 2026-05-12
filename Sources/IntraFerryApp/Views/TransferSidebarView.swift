import SwiftUI

struct TransferSidebarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("接收根")
            if state.remoteRoots.isEmpty {
                Text("刷新后显示")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.remoteRoots) { root in
                    sidebarButton(title: root.displayName, subtitle: root.path, systemImage: "externaldrive") {
                        Task { await state.browseRemotePath(root.path) }
                    }
                }
            }

            Divider()

            sectionTitle("最近目标")
            if state.recentRemoteTargets.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.recentRemoteTargets, id: \.self) { path in
                    sidebarButton(title: URL(fileURLWithPath: path).lastPathComponent, subtitle: path, systemImage: "clock") {
                        Task { await state.browseRemotePath(path) }
                    }
                }
            }

            Spacer(minLength: 12)

            sectionTitle("当前目标")
            Text(state.hasRemoteSendTarget ? state.trimmedRemoteSendTarget : "未选择")
                .font(.caption)
                .foregroundStyle(state.hasRemoteSendTarget ? .primary : .secondary)
                .lineLimit(3)
        }
        .padding(12)
        .frame(width: 180)
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
    }

    private func sidebarButton(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title.isEmpty ? subtitle : title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
