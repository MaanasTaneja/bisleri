import SwiftUI

struct ActivityLogView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ACCESS LOG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .tracking(1)
            
            VStack(spacing: 8) {
                if state.accessLog.isEmpty {
                    Text("Ready for connections")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(state.accessLog.prefix(5)) { entry in
                        HStack(spacing: 8) {
                            Text(entry.client.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                            
                            Text(entry.action)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary.opacity(0.8))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(entry.relativeTime)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}
