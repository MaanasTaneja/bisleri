import SwiftUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @EnvironmentObject private var state: AppState
    @State private var isTargetedForDrop = false

    var body: some View {
        VStack(spacing: 16) {
            screenshotStatusBox
            fileDropBox

            HStack(spacing: 12) {
                Button {
                    state.saveClipboard()
                } label: {
                    Label("Save Clipboard", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    state.captureScreenshot()
                } label: {
                    Label(screenshotButtonTitle, systemImage: screenshotButtonIcon)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(state.screenshotStatus.isBusy)
            }
        }
    }

    private var fileDropBox: some View {
        VStack(spacing: 8) {
            Image(systemName: fileDropIcon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(fileDropTint)
            
            VStack(spacing: 2) {
                Text(fileDropTitle)
                    .font(.subheadline.weight(.semibold))
                Text(fileDropSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
            
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargetedForDrop ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.5, dash: isTargetedForDrop ? [] : [5, 4])
                )
        }
        .background(isTargetedForDrop ? Color.accentColor.opacity(0.05) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
        .animation(.spring(response: 0.3), value: isTargetedForDrop)
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
        case .uploading: return "arrow.up.doc.fill"
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
        case .idle: return isTargetedForDrop ? "Release to ingest" : "Drop a file"
        }
    }

    private var fileDropSubtitle: String {
        switch state.fileUploadStatus {
        case .uploading(let msg), .completed(let msg), .failed(let msg):
            return msg
        case .idle:
            return "PDFs, text, code, JSON, markdown."
        }
    }

    private var screenshotStatusBox: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.12))
                    .frame(width: 56, height: 56)
                
                statusIcon
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(statusTint)
                
                if state.screenshotStatus.isBusy {
                    Circle()
                        .stroke(statusTint.opacity(0.2), lineWidth: 3)
                        .frame(width: 64, height: 64)
                    
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(statusTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(state.screenshotStatus.isBusy ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: state.screenshotStatus.isBusy)
                }
            }

            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.headline)
                
                Text(statusSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary.opacity(0.3))
            
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.secondary.opacity(0.1), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state.screenshotStatus {
        case .capturing:
            Image(systemName: "camera.viewfinder")
        case .processing:
            Image(systemName: "cpu")
        case .completed:
            Image(systemName: "checkmark")
        case .failed:
            Image(systemName: "exclamationmark.triangle")
        case .idle:
            Image(systemName: "camera.fill")
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
            return "Captured"
        case .processing:
            return "Processing"
        case .completed:
            return "Saved"
        case .failed:
            return "Failed"
        case .idle:
            return "Ready"
        }
    }

    private var statusSubtitle: String {
        switch state.screenshotStatus {
        case .capturing:
            return "Preparing image..."
        case .processing(let message):
            return message
        case .completed(let message):
            return message
        case .failed(let message):
            return message
        case .idle:
            return "Capture screen to memory."
        }
    }

    private var screenshotButtonTitle: String {
        state.screenshotStatus.isBusy ? "Processing" : "Screenshot"
    }

    private var screenshotButtonIcon: String {
        state.screenshotStatus.isBusy ? "hourglass" : "camera"
    }
}
