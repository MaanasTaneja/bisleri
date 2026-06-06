import SwiftUI

private let collectionPalette: [String: Color] = [
    "filesystem": .blue,
    "messages": .green,
    "browser": .orange,
    "misc": .purple
]

private let collectionOrder = ["filesystem", "messages", "browser", "misc"]

struct MemoryViewerView: View {
    @StateObject private var model = MemoryViewerModel()
    @State private var selectedCollection: String?
    @State private var selectedItem: MemoryItem?

    var body: some View {
        HSplitView {
            graphPane
                .frame(minWidth: 380)
            detailPane
                .frame(minWidth: 360)
        }
        .frame(minWidth: 820, minHeight: 540)
        .task { await model.refresh() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .navigationTitle("Memory Map")
    }

    private var graphPane: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            GeometryReader { proxy in
                GraphCanvas(
                    counts: model.counts,
                    selected: selectedCollection,
                    size: proxy.size,
                    onSelect: { name in
                        selectedCollection = name
                        selectedItem = nil
                    }
                )
            }
            if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .foregroundStyle(.secondary)
            } else if model.items.isEmpty && !model.isLoading {
                VStack(spacing: 6) {
                    Text("No memories yet")
                        .font(.headline)
                    Text("Start the server and capture something.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let collection = selectedCollection {
                detailHeader(for: collection)
                Divider()
                itemList(for: collection)
            } else {
                summaryView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func detailHeader(for collection: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(collectionPalette[collection] ?? .gray)
                .frame(width: 14, height: 14)
            Text(collection.capitalized)
                .font(.title3.weight(.semibold))
            Spacer()
            Text("\(model.counts[collection] ?? 0) items")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func itemList(for collection: String) -> some View {
        let items = model.items.filter { $0.collection == collection }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    MemoryRow(item: item, isExpanded: selectedItem?.id == item.id) {
                        if selectedItem?.id == item.id {
                            selectedItem = nil
                        } else {
                            selectedItem = item
                        }
                    }
                }
                if items.isEmpty {
                    Text("No items in this collection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                }
            }
            .padding(16)
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your memory at a glance")
                .font(.title3.weight(.semibold))
            Text("Click a collection node to inspect what is stored there.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            ForEach(collectionOrder, id: \.self) { name in
                HStack {
                    Circle()
                        .fill(collectionPalette[name] ?? .gray)
                        .frame(width: 10, height: 10)
                    Text(name.capitalized)
                    Spacer()
                    Text("\(model.counts[name] ?? 0)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
            }
            Spacer()
        }
        .padding(20)
    }
}

private struct MemoryRow: View {
    let item: MemoryItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.summary)
                        .font(.callout)
                        .lineLimit(isExpanded ? nil : 2)
                    HStack(spacing: 6) {
                        Text(item.source)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                        Text(formattedTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isExpanded {
                Divider()
                Text(item.text)
                    .font(.callout)
                    .textSelection(.enabled)
                if !item.metadata.isEmpty {
                    Text("Metadata")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(item.metadata.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)
                            Text(item.metadata[key]?.displayString ?? "")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var formattedTimestamp: String {
        guard let date = ISO8601DateFormatter().date(from: item.timestamp) else { return item.timestamp }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct GraphCanvas: View {
    let counts: [String: Int]
    let selected: String?
    let size: CGSize
    let onSelect: (String) -> Void

    var body: some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) * 0.32

        ZStack {
            ForEach(Array(collectionOrder.enumerated()), id: \.element) { index, name in
                let position = nodePosition(index: index, total: collectionOrder.count, center: center, radius: radius)
                ConnectionLine(from: center, to: position, isActive: selected == name)
            }

            CenterNode()
                .position(center)

            ForEach(Array(collectionOrder.enumerated()), id: \.element) { index, name in
                let position = nodePosition(index: index, total: collectionOrder.count, center: center, radius: radius)
                CollectionNode(
                    name: name,
                    count: counts[name] ?? 0,
                    isSelected: selected == name
                )
                .position(position)
                .onTapGesture { onSelect(name) }
            }
        }
    }

    private func nodePosition(index: Int, total: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        let angle: CGFloat = (2 * .pi / CGFloat(total)) * CGFloat(index) - .pi / 2
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}

private struct ConnectionLine: View {
    let from: CGPoint
    let to: CGPoint
    let isActive: Bool

    var body: some View {
        Path { path in
            path.move(to: from)
            path.addLine(to: to)
        }
        .stroke(
            isActive ? Color.accentColor : Color.secondary.opacity(0.35),
            style: StrokeStyle(lineWidth: isActive ? 2.5 : 1.5, lineCap: .round)
        )
    }
}

private struct CenterNode: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: 110, height: 110)
            Circle()
                .stroke(Color.accentColor, lineWidth: 2)
                .frame(width: 84, height: 84)
            VStack(spacing: 2) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("ContextKit")
                    .font(.caption.weight(.semibold))
            }
        }
    }
}

private struct CollectionNode: View {
    let name: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        let color = collectionPalette[name] ?? .gray
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(color.opacity(isSelected ? 0.35 : 0.18))
                    .frame(width: 78, height: 78)
                Circle()
                    .stroke(color, lineWidth: isSelected ? 3 : 1.5)
                    .frame(width: 66, height: 66)
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(color)
            }
            Text(name.capitalized)
                .font(.caption.weight(.semibold))
        }
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

@MainActor
private final class MemoryViewerModel: ObservableObject {
    @Published var items: [MemoryItem] = []
    @Published var counts: [String: Int] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let client = MemoryClient()

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            let fetched = try await client.fetchMemory(limit: 500)
            items = fetched
            var tally: [String: Int] = [:]
            for item in fetched {
                tally[item.collection, default: 0] += 1
            }
            counts = tally
        } catch {
            errorMessage = "Could not load memory. Is the server running?"
            items = []
            counts = [:]
        }
        isLoading = false
    }
}
