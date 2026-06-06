import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    enum ScreenshotStatus: Equatable {
        case idle
        case capturing
        case processing(String)
        case completed(String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .capturing, .processing:
                return true
            case .idle, .completed, .failed:
                return false
            }
        }
    }

    @Published var serverRunning = false
    @Published var recentItems: [CaptureItem] = []
    @Published var screenshotStatus: ScreenshotStatus = .idle
    @Published var clients: [ConnectedClient] = [
        ConnectedClient(name: "Claude", status: .disconnected),
        ConnectedClient(name: "ChatGPT", status: .disconnected),
        ConnectedClient(name: "Cursor", status: .disconnected)
    ]
    @Published var openAIAPIKey: String {
        didSet {
            UserDefaults.standard.set(openAIAPIKey, forKey: "openAIAPIKey")
        }
    }
    @Published var accessLog: [AccessLogEntry] = []
    @Published var allowedFolders: [URL] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Documents", "Desktop", "Downloads"].map { home.appendingPathComponent($0) }
    }()

    let server = MCPServerProcess()
    let ingestion = IngestionPipeline()
    let permissions = PermissionManager()
    let clientRegistry = ClientRegistry()

    init() {
        self.openAIAPIKey = UserDefaults.standard.string(forKey: "openAIAPIKey") ?? ""
    }

    func toggleServer() {
        if serverRunning {
            server.stop()
            serverRunning = false
        } else {
            server.start(openAIAPIKey: openAIAPIKey)
            serverRunning = true
        }
    }

    func saveClipboard() {
        Task {
            if let text = ClipboardMonitor.currentText() {
                _ = try? await ingestion.ingest(text: text, collection: "misc", metadata: ["source": "clipboard"])
                recentItems.insert(CaptureItem(title: "Clipboard", summary: text, source: "clipboard"), at: 0)
            }
        }
    }

    func captureScreenshot() {
        guard !screenshotStatus.isBusy else { return }
        Task { await captureAndPollScreenshot() }
    }

    private func captureAndPollScreenshot() async {
        screenshotStatus = .capturing
        guard let image = ScreenCaptureManager.captureMainDisplay(),
              let data = image.pngData() else {
            await finishScreenshot(status: .failed("Could not capture the screen."))
            return
        }

        do {
            screenshotStatus = .processing("Uploading screenshot...")
            let job = try await ingestion.createScreenshotJob(
                imageData: data,
                metadata: ["source": "screenshot"]
            )
            let completedJob = try await pollScreenshotJob(id: job.id)
            let summary = completedJob.result?.metadata["summary"] ?? "Screenshot saved to memory"
            recentItems.insert(CaptureItem(title: "Screenshot", summary: summary, source: "screenshot"), at: 0)
            await finishScreenshot(status: .completed("Screenshot saved to memory."))
        } catch {
            await finishScreenshot(status: .failed(error.localizedDescription))
        }
    }

    private func pollScreenshotJob(id: String) async throws -> ScreenshotJob {
        while true {
            try await Task.sleep(nanoseconds: 600_000_000)
            let job = try await ingestion.fetchScreenshotJob(id: id)
            switch job.status {
            case .processing:
                screenshotStatus = .processing("Processing screenshot...")
            case .completed:
                return job
            case .failed:
                throw ScreenshotJobError.server(job.error ?? "Screenshot processing failed.")
            }
        }
    }

    private func finishScreenshot(status: ScreenshotStatus) async {
        screenshotStatus = status
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        if screenshotStatus == status {
            screenshotStatus = .idle
        }
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
