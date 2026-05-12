import SwiftUI

struct TransferWindowView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TransferHeaderView(state: state, openSettings: openSettings)
            RemotePathPickerView(state: state)
            DropZoneView { urls in
                Task {
                    await state.sendDroppedFiles(urls)
                }
            }
            TaskRowView(name: state.transferSummary, progress: state.transferProgress)
        }
        .padding()
        .frame(width: 680, height: 540)
    }
}
