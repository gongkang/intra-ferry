import SwiftUI

struct TransferDropOverlayView: View {
    var targetPath: String

    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.88)
            VStack(spacing: 14) {
                Image(systemName: targetPath.isEmpty ? "exclamationmark.triangle" : "tray.and.arrow.up.fill")
                    .font(.system(size: 48, weight: .semibold))
                Text(targetPath.isEmpty ? "先选择发送目标" : "松开发送")
                    .font(.system(size: 30, weight: .bold))
                Text(targetPath.isEmpty ? "请先在路径输入框中填写远端目录" : "发送到 \(targetPath)")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 32)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [10]))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(28)
            }
        }
        .transition(.opacity)
    }
}
