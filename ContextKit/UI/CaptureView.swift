import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @EnvironmentObject private var state: AppState
    @State private var isTargetedForDrop = false

    var body: some View {
        VStack(spacing: 12) {
            screenshotStatusBox
            fileDropBox

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

    private var fileDropBox: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
                isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.35),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTargetedForDrop ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .frame(height: 90)
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: fileDropIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(fileDropTint)
                    Text(fileDropTitle)
                        .font(.callout.weight(.medium))
                    Text(fileDropSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
                handleDrop(providers: providers)
            }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                state.ingestDroppedFile(url: url)
            }
        }
        return true
    }

    private var fileDropIcon: String {
        switch state.fileUploadStatus {
        case .uploading: return "arrow.up.doc"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle: return "doc.badge.plus"
        }
    }

    private var fileDropTint: Color {
        switch state.fileUploadStatus {
        case .completed: return .green
        case .failed: return .red
        case .uploading: return .accentColor
        case .idle: return isTargetedForDrop ? .accentColor : .secondary
        }
    }

    private var fileDropTitle: String {
        switch state.fileUploadStatus {
        case .uploading: return "Uploading file"
        case .completed: return "File saved"
        case .failed: return "Upload failed"
        case .idle: return isTargetedForDrop ? "Release to ingest" : "Drop a file to add to memory"
        }
    }

    private var fileDropSubtitle: String {
        switch state.fileUploadStatus {
        case .uploading(let msg), .completed(let msg), .failed(let msg):
            return msg
        case .idle:
            return "PDFs, text, code, JSON, markdown — summarized and stored."
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
