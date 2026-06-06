import Foundation

final class MCPServerProcess {
    private var process: Process?

    func start(port: Int = 3847, token: String = "dev-token", openAIAPIKey: String = "") {
        guard process == nil else { return }

        guard let repoRoot = Self.findRepoRoot() else {
            NSLog("MCPServerProcess: could not locate repo root containing mcp_server/main.py")
            return
        }

        let (executable, leadingArgs) = Self.resolvePython(repoRoot: repoRoot)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = leadingArgs + ["-m", "mcp_server.main", "--port", "\(port)", "--token", token]
        process.currentDirectoryURL = repoRoot
        var environment = ProcessInfo.processInfo.environment
        let trimmedKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            environment["OPENAI_API_KEY"] = trimmedKey
        }
        process.environment = environment

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("MCPServerProcess: failed to launch \(executable): \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private static func findRepoRoot() -> URL? {
        let fm = FileManager.default
        var dir = Bundle.main.bundleURL.deletingLastPathComponent()
        for _ in 0..<10 {
            let marker = dir.appendingPathComponent("mcp_server/main.py")
            if fm.fileExists(atPath: marker.path) {
                return dir
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    private static func resolvePython(repoRoot: URL) -> (executable: String, leadingArgs: [String]) {
        let venvPython = repoRoot.appendingPathComponent(".venv/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return (venvPython, [])
        }
        return ("/usr/bin/env", ["python3"])
    }
}
