import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            CaptureView()
            searchField
            recentList
            Divider()
            PrivacyControlView()
        }
        .padding(16)
        .frame(width: 390)
    }

    private var header: some View {
        HStack {
            Text("ContextKit")
                .font(.headline)
            Spacer()
            Button {
                openWindow(id: "memory-viewer")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "circle.hexagongrid")
            }
            .buttonStyle(.borderless)
            .help("Memory Map")
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("Search your memory...", text: $query)
                .textFieldStyle(.plain)
        }
        .padding(10)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.subheadline).foregroundStyle(.secondary)
            ForEach(state.recentItems.prefix(5)) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout)
                    Text(item.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}
