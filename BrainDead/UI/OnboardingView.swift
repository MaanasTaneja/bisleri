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
            VStack(alignment: .leading, spacing: 32) {
                header
                
                VStack(spacing: 32) {
                    statusCard
                    foldersSection
                    connectSection
                }
            }
            .padding(32)
            .frame(width: 560)
        }
        .frame(width: 560, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 64, height: 64)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to BrainDead")
                    .font(.system(size: 28, weight: .bold))
                Text("Local-first memory. Private and secure.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Server Status")
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("ACTIVE")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green.opacity(0.1), in: Capsule())
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(serverURL)
                        .font(.system(.subheadline, design: .monospaced))
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("SSE Endpoint:")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text(sseURL)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(20)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.secondary.opacity(0.1), lineWidth: 0.5)
        }
    }

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Privacy Boundaries")
                        .font(.headline)
                    Text("BrainDead only indexes files within these folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    pickFolder()
                } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            VStack(spacing: 8) {
                ForEach(defaultFolderNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "folder.fill").foregroundStyle(.tint)
                        Text(name)
                            .font(.subheadline)
                        Spacer()
                        Text("SYSTEM")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }

                ForEach(customFolders, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text((path as NSString).abbreviatingWithTildeInPath)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            removeFolder(path)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }

                if customFolders.isEmpty {
                    HStack {
                        Text("No custom folders added.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("App Integration")
                .font(.headline)

            VStack(spacing: 16) {
                // Claude Integration Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                        Text("Claude Desktop")
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text("Recommended")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.1), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    
                    Text("Automatically add BrainDead as an MCP server to your Claude configuration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button {
                            connectClaudeDesktop()
                        } label: {
                            Label("Easy Connect", systemImage: "link")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        
                        Button {
                            copy(claudeConfigSnippet)
                            copiedClaudeSnippet = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedClaudeSnippet = false }
                        } label: {
                            Label(copiedClaudeSnippet ? "Copied" : "Copy Settings", systemImage: copiedClaudeSnippet ? "checkmark" : "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    if let message = claudeStatusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: claudeStatusIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(claudeStatusIsError ? .red : .green)
                            Text(message)
                                .font(.caption2)
                        }
                        .padding(10)
                        .background(claudeStatusIsError ? .red.opacity(0.05) : .green.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
                
                // ChatGPT Integration Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.blue)
                        Text("ChatGPT Desktop")
                            .font(.subheadline.weight(.bold))
                    }
                    
                    Text("Add as a connector using the SSE URL below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text(sseURL)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copy(sseURL)
                            copiedSSEURL = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedSSEURL = false }
                        } label: {
                            Image(systemName: copiedSSEURL ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(copiedSSEURL ? .green : .accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.secondary.opacity(0.1), lineWidth: 0.5)
                    }
                }
                .padding(20)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
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
            "braindead": {
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
            mcpServers["braindead"] = [
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
