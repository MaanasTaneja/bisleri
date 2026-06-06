import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 12) {
            screenshotStatusBox

            HStack {
                Button {
                    state.saveClipboard()
                } label: {
                    Label("Save Clipboard", systemImage: "doc.on.clipboard")
                }

                Button {
                    state.captureScreenshot()
                } label: {
                    Label(screenshotButtonTitle, systemImage: screenshotButtonIcon)
                }
                .disabled(state.screenshotStatus.isBusy)
            }
        }
    }

    private var screenshotStatusBox: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.quaternary)
            .frame(height: 150)
            .overlay {
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.background.opacity(0.55))
                            .frame(width: 72, height: 54)
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
                            }

                        statusIcon
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(statusTint)
                    }

                    Text(statusTitle)
                        .font(.callout.weight(.medium))

                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .padding(.horizontal, 18)
            }
            .overlay(alignment: .topTrailing) {
                if state.screenshotStatus.isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .padding(10)
                }
            }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.screenshotStatus {
        case .capturing:
            Image(systemName: "camera.viewfinder")
        case .processing:
            Image(systemName: "camera.metering.center.weighted")
        case .completed:
            Image(systemName: "checkmark.circle.fill")
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        case .idle:
            Image(systemName: "camera")
        }
    }

    private var statusTint: Color {
        switch state.screenshotStatus {
        case .completed:
            return .green
        case .failed:
            return .red
        case .capturing, .processing:
            return .accentColor
        case .idle:
            return .secondary
        }
    }

    private var statusTitle: String {
        switch state.screenshotStatus {
        case .capturing:
            return "Screenshot captured"
        case .processing:
            return "Processing screenshot"
        case .completed:
            return "Screenshot saved"
        case .failed:
            return "Screenshot failed"
        case .idle:
            return "Ready for screenshot"
        }
    }

    private var statusSubtitle: String {
        switch state.screenshotStatus {
        case .capturing:
            return "Preparing image for memory."
        case .processing(let message):
            return message
        case .completed(let message):
            return message
        case .failed(let message):
            return message
        case .idle:
            return "Capture the current screen and add it to memory."
        }
    }

    private var screenshotButtonTitle: String {
        state.screenshotStatus.isBusy ? "Processing" : "Screenshot"
    }

    private var screenshotButtonIcon: String {
        state.screenshotStatus.isBusy ? "hourglass" : "camera"
    }
}
