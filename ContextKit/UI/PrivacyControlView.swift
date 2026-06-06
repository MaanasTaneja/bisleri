import SwiftUI

struct PrivacyControlView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("OpenAI API Key").font(.subheadline).foregroundStyle(.secondary)
                SecureField("Required for screenshot OCR", text: $state.openAIAPIKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(state.serverRunning)
            }

            HStack {
                Label(state.serverRunning ? "Server On" : "Server Off", systemImage: state.serverRunning ? "circle.fill" : "circle")
                    .foregroundStyle(state.serverRunning ? .green : .secondary)
                Spacer()
                Button(state.serverRunning ? "Stop" : "Start") {
                    state.toggleServer()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Connections").font(.subheadline).foregroundStyle(.secondary)
                ForEach(state.clients) { client in
                    HStack {
                        Text(client.name)
                        Spacer()
                        Text(client.status.rawValue).foregroundStyle(.secondary)
                        Button("Revoke") {
                            state.clientRegistry.revoke(client)
                        }
                        .disabled(client.status == .disconnected)
                    }
                    .font(.caption)
                }
            }

            ActivityLogView()
        }
    }
}
