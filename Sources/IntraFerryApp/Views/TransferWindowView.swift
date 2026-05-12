import SwiftUI

struct TransferWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transfer")
                .font(.title2)
            RemotePathPickerView(state: state)
            DropZoneView { urls in
                Task {
                    await state.sendDroppedFiles(urls)
                }
            }
            TaskRowView(name: state.transferSummary, progress: state.transferProgress)
        }
        .padding()
        .frame(width: 560, height: 420)
    }
}
