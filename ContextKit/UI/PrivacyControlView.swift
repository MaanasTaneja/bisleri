import SwiftUI

struct PrivacyControlView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
