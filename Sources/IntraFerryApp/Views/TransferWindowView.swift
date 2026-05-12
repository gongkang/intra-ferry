import SwiftUI

struct TransferWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("传输")
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
        .frame(width: 680, height: 540)
    }
}
