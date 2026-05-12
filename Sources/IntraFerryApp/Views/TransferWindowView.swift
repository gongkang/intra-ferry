import SwiftUI
import UniformTypeIdentifiers

struct TransferWindowView: View {
    @ObservedObject var state: AppState
    var openSettings: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
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
        .frame(minWidth: 760, minHeight: 520)
    }
}
