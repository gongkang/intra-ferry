import SwiftUI

struct TransferHeaderView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(state.transferPeerTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Label(state.transferPeerStatusText, systemImage: statusIcon)
                .font(.caption)
                .foregroundStyle(statusColor)

            Button(action: openSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .help("打开设置")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusIcon: String {
        switch state.remotePeerReachability {
        case .online:
            return "checkmark.circle.fill"
        case .checking:
            return "clock"
        case .offline:
            return "xmark.circle.fill"
        case .notConfigured:
            return "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch state.remotePeerReachability {
        case .online:
            return .green
        case .checking:
            return .secondary
        case .offline:
            return .red
        case .notConfigured:
            return .orange
        }
    }
}
