import Foundation

final class MCPServerProcess {
    private var process: Process?

    func start(port: Int = 3847, token: String = "dev-token") {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-m", "mcp_server.main", "--port", "\(port)", "--token", token]
        process.currentDirectoryURL = Bundle.main.resourceURL
        try? process.run()
        self.process = process
    }

    func stop() {
        process?.terminate()
        process = nil
    }
}
