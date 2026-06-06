import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var serverRunning = false
    @Published var recentItems: [CaptureItem] = []
    @Published var clients: [ConnectedClient] = [
        ConnectedClient(name: "Claude", status: .disconnected),
        ConnectedClient(name: "ChatGPT", status: .disconnected),
        ConnectedClient(name: "Cursor", status: .disconnected)
    ]
    @Published var accessLog: [AccessLogEntry] = []
    @Published var allowedFolders: [URL] = []

    let server = MCPServerProcess()
    let ingestion = IngestionPipeline()
    let permissions = PermissionManager()
    let clientRegistry = ClientRegistry()

    func toggleServer() {
        if serverRunning {
            server.stop()
            serverRunning = false
        } else {
            server.start()
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
}
