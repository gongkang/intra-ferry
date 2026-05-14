import SwiftUI

struct TransferFooterView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(state.hasRemoteSendTarget ? "发送目标：\(state.trimmedRemoteSendTarget)" : "发送目标：未选择")
                    .font(.caption)
                    .foregroundStyle(state.hasRemoteSendTarget ? Color.secondary : Color.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Toggle("包含隐藏文件", isOn: $state.transferIncludesHiddenFiles)
                    .font(.caption)
                    .toggleStyle(.checkbox)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(state.transferSummary)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)

            ProgressView(value: state.transferProgress)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var progressText: String {
        "\(Int((state.transferProgress * 100).rounded()))%"
    }
}
