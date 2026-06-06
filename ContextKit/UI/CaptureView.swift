import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(height: 150)
                .overlay(Image(systemName: "macwindow").font(.largeTitle).foregroundStyle(.secondary))

            HStack {
                Button {
                    state.saveClipboard()
                } label: {
                    Label("Save Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    Task { await ScreenshotCapture.captureAndIngest(state: state) }
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
            }
        }
    }
}
