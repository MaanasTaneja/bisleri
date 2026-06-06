import SwiftUI

struct PrivacyControlView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // API Key Section
            VStack(alignment: .leading, spacing: 8) {
                Text("OPENAI API KEY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                HStack(spacing: 8) {
                    SecureField("sk-...", text: $state.openAIAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    
                    if !state.openAIAPIKey.isEmpty {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 14))
                    }
                }
                .disabled(state.serverRunning)
            }

            // Server Control
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(state.serverRunning ? Color.green.opacity(0.1) : Color.secondary.opacity(0.1))
                        .frame(height: 50)
                    
                    HStack(spacing: 12) {
                        Circle()
                            .fill(state.serverRunning ? .green : .secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .shadow(color: state.serverRunning ? .green.opacity(0.3) : .clear, radius: 2)
                        
                        Text(state.serverRunning ? "SERVER ACTIVE" : "SERVER STANDBY")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(state.serverRunning ? .green : .secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                state.toggleServer()
                            }
                        } label: {
                            Text(state.serverRunning ? "STOP" : "START")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(state.serverRunning ? .red.opacity(0.1) : Color.accentColor, in: Capsule())
                                .foregroundStyle(state.serverRunning ? .red : .white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }
            }

            // Connections Section
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE CONNECTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                
                VStack(spacing: 8) {
                    if state.clients.isEmpty {
                        Text("No external apps connected")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(state.clients) { client in
                            HStack(spacing: 12) {
                                Image(systemName: iconForClient(client))
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 12))
                                
                                Text(client.name)
                                    .font(.system(size: 13, weight: .medium))
                                
                                Spacer()
                                
                                if client.status == .connected {
                                    Text("LIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.green.opacity(0.1), in: Capsule())
                                }
                                
                                Button("Revoke") {
                                    state.clientRegistry.revoke(client)
                                }
                                .font(.system(size: 11))
                                .buttonStyle(.plain)
                                .foregroundStyle(.red.opacity(0.8))
                                .disabled(client.status == .disconnected)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }

            ActivityLogView()
        }
    }

    private func iconForClient(_ client: ConnectedClient) -> String {
        switch client.name.lowercased() {
        case "claude": return "bolt.fill"
        case "chatgpt": return "sparkles"
        case "cursor": return "chevron.left.forwardslash.chevron.right"
        default: return "app.badge.fill"
        }
    }
}
