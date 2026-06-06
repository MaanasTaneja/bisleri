import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Activity").font(.subheadline).foregroundStyle(.secondary)
            ForEach(state.accessLog.prefix(4)) { entry in
                HStack {
                    Text(entry.client)
                    Text(entry.action).foregroundStyle(.secondary)
                    Spacer()
                    Text(entry.relativeTime).foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}
