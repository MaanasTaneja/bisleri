import Foundation

final class MCPServerProcess {
    private var process: Process?

    func start(port: Int = 3847, token: String = "dev-token", openAIAPIKey: String = "") {
        guard process == nil else { return }

        guard let repoRoot = Self.findRepoRoot() else {
            NSLog("MCPServerProcess: could not locate repo root containing mcp_server/main.py")
            return
        }

        Self.killProcessesOnPort(port)

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
        environment["CONTEXTKIT_ALLOWED_FOLDERS"] = Self.defaultAllowedFolders()
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

    private static func killProcessesOnPort(_ port: Int) {
        let lsof = Process()
        lsof.executableURL = URL(fileURLWithPath: "/bin/sh")
        lsof.arguments = ["-c", "lsof -ti tcp:\(port)"]
        let pipe = Pipe()
        lsof.standardOutput = pipe
        lsof.standardError = Pipe()
        do {
            try lsof.run()
            lsof.waitUntilExit()
        } catch {
            return
        }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return }
        let pids = output.split(whereSeparator: { $0.isNewline || $0.isWhitespace }).map(String.init)
        for pid in pids where !pid.isEmpty {
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/bin/kill")
            kill.arguments = ["-9", pid]
            try? kill.run()
            kill.waitUntilExit()
        }
        if !pids.isEmpty {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func defaultAllowedFolders() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = ["Documents", "Desktop", "Downloads"].map { home.appendingPathComponent($0).path }

        let stored = UserDefaults.standard.string(forKey: "ck.customAllowedFolders") ?? ""
        let custom = stored
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        for path in custom where !paths.contains(path) {
            paths.append(path)
        }
        return paths.joined(separator: ":")
    }

    private static func resolvePython(repoRoot: URL) -> (executable: String, leadingArgs: [String]) {
        let venvPython = repoRoot.appendingPathComponent(".venv/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            return (venvPython, [])
        }
        return ("/usr/bin/env", ["python3"])
    }
}
