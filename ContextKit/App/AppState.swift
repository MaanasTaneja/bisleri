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
}
