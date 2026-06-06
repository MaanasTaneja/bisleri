import AppKit
import SwiftUI

private let customFoldersKey = "ck.customAllowedFolders"
private let serverURL = "http://127.0.0.1:3847"
private let sseURL = "http://127.0.0.1:3847/sse"

struct OnboardingView: View {
    @AppStorage(customFoldersKey) private var customFolderPaths: String = ""
    @State private var copiedClaudeSnippet = false
    @State private var copiedSSEURL = false
    @State private var claudeStatusMessage: String?
    @State private var claudeStatusIsError = false

    private let defaultFolderNames = ["Documents", "Desktop", "Downloads"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                Divider()
                statusSection
                Divider()
                foldersSection
                Divider()
                connectSection
            }
            .padding(28)
            .frame(width: 560)
        }
        .frame(width: 560, height: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ContextKit").font(.title.weight(.semibold))
            Text("Local-first memory you can share with Claude and ChatGPT.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Local server").font(.headline)
            HStack(spacing: 8) {
                Image(systemName: "circle.fill").foregroundStyle(.green).font(.caption)
                Text(serverURL).font(.callout.monospaced())
            }
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("MCP SSE:").foregroundStyle(.secondary)
                Text(sseURL).font(.callout.monospaced()).textSelection(.enabled)
            }
            .font(.callout)
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Allowed folders").font(.headline)
                Spacer()
                Button {
                    pickFolder()
                } label: {
                    Label("Add folder", systemImage: "plus.circle")
                }
            }

            Text("ContextKit can only index files inside these folders.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(defaultFolderNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text(name)
                        Spacer()
                        Text("default")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    .padding(.vertical, 4)
                }

                ForEach(customFolders, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeFolder(path)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                }

                if customFolders.isEmpty {
                    Text("No custom folders added yet.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your apps").font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Claude Desktop").font(.subheadline.weight(.semibold))
                Text("One-click setup — writes \(claudeConfigPath) and adds the ContextKit MCP server.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        connectClaudeDesktop()
                    } label: {
                        Label("Connect Claude Desktop", systemImage: "link.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        copy(claudeConfigSnippet)
                        copiedClaudeSnippet = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedClaudeSnippet = false }
                    } label: {
                        Label(copiedClaudeSnippet ? "Copied" : "Copy snippet", systemImage: copiedClaudeSnippet ? "checkmark" : "doc.on.doc")
                    }
                }

                if let message = claudeStatusMessage {
                    HStack(spacing: 6) {
                        Image(systemName: claudeStatusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(claudeStatusIsError ? .orange : .green)
                        Text(message)
                            .font(.caption)
                    }
                    .padding(.top, 4)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("ChatGPT Desktop").font(.subheadline.weight(.semibold))
                Text("Settings → Connectors → Add MCP server, then paste this URL:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(sseURL)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        copy(sseURL)
                        copiedSSEURL = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedSSEURL = false }
                    } label: {
                        Image(systemName: copiedSSEURL ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

                Text("Note: ChatGPT may require an HTTPS public URL (e.g. via an OpenAI Secure MCP Tunnel) — localhost isn't always accepted.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var customFolders: [String] {
        customFolderPaths
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow"
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            var folders = customFolders
            if !folders.contains(path) {
                folders.append(path)
                customFolderPaths = folders.joined(separator: "\n")
            }
        }
    }

    private func removeFolder(_ path: String) {
        customFolderPaths = customFolders.filter { $0 != path }.joined(separator: "\n")
    }

    private func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private var claudeConfigPath: String {
        "~/Library/Application Support/Claude/claude_desktop_config.json"
    }

    private var claudeConfigSnippet: String {
        """
        {
          "mcpServers": {
            "contextkit": {
              "command": "npx",
              "args": ["-y", "mcp-remote", "\(sseURL)"]
            }
          }
        }
        """
    }

    private func connectClaudeDesktop() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let claudeDir = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Claude", isDirectory: true)
        let configURL = claudeDir.appendingPathComponent("claude_desktop_config.json")

        do {
            try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)

            var config: [String: Any] = [:]
            if let data = try? Data(contentsOf: configURL),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                config = parsed
            }

            var mcpServers = config["mcpServers"] as? [String: Any] ?? [:]
            mcpServers["contextkit"] = [
                "command": "npx",
                "args": ["-y", "mcp-remote", sseURL]
            ] as [String: Any]
            config["mcpServers"] = mcpServers

            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configURL, options: .atomic)

            claudeStatusIsError = false
            claudeStatusMessage = "Added to claude_desktop_config.json. Restart Claude Desktop to pick it up."
        } catch {
            claudeStatusIsError = true
            claudeStatusMessage = "Failed to write config: \(error.localizedDescription)"
        }
    }
}
