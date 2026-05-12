import SwiftUI
import UniformTypeIdentifiers

struct TransferWindowView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TransferHeaderView(state: state, openSettings: openSettings)
                Divider()
                HStack(spacing: 0) {
                    TransferSidebarView(state: state)
                    Divider()
                    RemotePathPickerView(state: state)
                }
                TransferFooterView(state: state)
            }

            if isDropTargeted {
                TransferDropOverlayView(targetPath: state.trimmedRemoteSendTarget)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .animation(.easeOut(duration: 0.12), value: isDropTargeted)
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted) { providers in
            guard state.hasRemoteSendTarget else {
                state.transferSummary = "请先选择发送目标"
                return true
            }

            FileDropLoader.loadURLs(from: providers) { urls in
                Task {
                    await state.sendDroppedFiles(urls)
                }
            }
            return true
        }
    }
}
