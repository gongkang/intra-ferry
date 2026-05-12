import SwiftUI

struct TaskRowView: View {
    var name: String
    var progress: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text(name)
            ProgressView(value: progress)
        }
    }
}
