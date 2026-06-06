import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    var body: some View {
        VStack(spacing: 20) {
            header
            
            VStack(spacing: 16) {
                CaptureView()
                searchField
                recentList
            }
            
            Divider()
            PrivacyControlView()
        }
        .padding(20)
        .frame(width: 390)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accentColor)
                Text("BrainDead")
                    .font(.headline.weight(.bold))
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Button {
                    openWindow(id: "memory-viewer")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 14))
                        .padding(6)
                        .background(.quaternary.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Memory Map")
                
                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14))
                        .padding(6)
                        .background(.quaternary.opacity(0.5), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search your memory...", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.secondary.opacity(0.1), lineWidth: 0.5)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                Spacer()
                if !state.recentItems.isEmpty {
                    Text("See all")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            
            VStack(spacing: 8) {
                if state.recentItems.isEmpty {
                    Text("No recent activity")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                } else {
                    ForEach(state.recentItems.prefix(3)) { item in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentColor.opacity(0.1))
                                    .frame(width: 32, height: 32)
                                Image(systemName: iconForItem(item))
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.accentColor)
                            }
                            
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                Text(item.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func iconForItem(_ item: CaptureItem) -> String {
        switch item.source {
        case "clipboard": return "doc.on.clipboard"
        case "screenshot": return "camera"
        case "file_upload": return "doc"
        default: return "sparkles"
        }
    }
}
