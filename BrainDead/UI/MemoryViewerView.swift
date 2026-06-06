import SwiftUI

private let collectionPalette: [String: Color] = [
    "filesystem": .blue,
    "messages": .green,
    "browser": .orange,
    "misc": .purple
]

private let defaultCollectionOrder = ["filesystem", "messages", "browser", "misc"]

struct MemoryViewerView: View {
    @StateObject private var model = MemoryViewerModel()
    @State private var selectedCollection: String?
    @State private var selectedItem: MemoryItem?
    @State private var newCollectionName = ""

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
                .overlay {
                    LinearGradient(
                        colors: [.accentColor.opacity(0.05), .clear, .accentColor.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            
            GeometryReader { proxy in
                GraphCanvas(
                    collections: model.collections,
                    counts: model.counts,
                    selected: selectedCollection,
                    size: proxy.size,
                    onSelect: { name in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedCollection = name
                            selectedItem = nil
                        }
                    },
                    onCenterTap: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedCollection = nil
                            selectedItem = nil
                        }
                    }
                )
            }
            
            if let error = model.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(24)
            } else if model.items.isEmpty && !model.isLoading {
                VStack(spacing: 8) {
                    Text("No memories yet")
                        .font(.headline)
                    Text("Start the server and capture something.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 32)
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
        HStack(spacing: 12) {
            Circle()
                .fill(collectionColor(collection))
                .frame(width: 12, height: 12)
                .shadow(color: collectionColor(collection).opacity(0.35), radius: 4)
            
            Text(collectionTitle(collection))
                .font(.title2.weight(.bold))
            
            Spacer()
            
            Text("\(model.counts[collection] ?? 0) items")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary.opacity(0.5), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    private func itemList(for collection: String) -> some View {
        let items = model.items.filter { $0.collection == collection }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    MemoryRow(item: item, isExpanded: selectedItem?.id == item.id) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            if selectedItem?.id == item.id {
                                selectedItem = nil
                            } else {
                                selectedItem = item
                            }
                        }
                    }
                }
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text("No items in this collection.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }
            }
            .padding(20)
        }
    }

    private var summaryView: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Memory Overview")
                    .font(.title.weight(.bold))
                Text("Select a node to explore stored context.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Actions")
                    .font(.headline)
                createCollectionControl
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Collections")
                    .font(.headline)
                
                ForEach(model.collections, id: \.self) { name in
                    Button {
                        withAnimation { selectedCollection = name }
                    } label: {
                        HStack {
                            Circle()
                                .fill(collectionColor(name))
                                .frame(width: 8, height: 8)
                            Text(collectionTitle(name))
                                .font(.body)
                            Spacer()
                            Text("\(model.counts[name] ?? 0)")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
        }
        .padding(28)
    }

    private var createCollectionControl: some View {
        HStack(spacing: 8) {
            TextField("Collection name...", text: $newCollectionName)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .onSubmit {
                    Task { await createCollection() }
                }
            Button {
                Task { await createCollection() }
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isCreatingCollection || newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func createCollection() async {
        let name = newCollectionName
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let created = await model.createCollection(name: name) {
            newCollectionName = ""
            selectedCollection = created
            selectedItem = nil
        }
    }
}

private struct MemoryRow: View {
    let item: MemoryItem
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.summary)
                        .font(.headline.weight(.medium))
                        .lineLimit(isExpanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Text(item.source.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(Color.accentColor)
                        
                        Text(formattedTimestamp)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Spacer()
                
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.body)
                    .foregroundStyle(.secondary.opacity(0.6))
                    .imageScale(.large)
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    Text(item.text)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .foregroundStyle(.primary.opacity(0.9))
                    
                    if !item.metadata.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Metadata")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                            
                            ForEach(item.metadata.keys.sorted(), id: \.self) { key in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(key)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    
                                    Text(item.metadata[key]?.displayString ?? "")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(isExpanded ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isExpanded ? Color.accentColor.opacity(0.3) : .secondary.opacity(0.1), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var formattedTimestamp: String {
        guard let date = ISO8601DateFormatter().date(from: item.timestamp) else { return item.timestamp }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct GraphCanvas: View {
    let collections: [String]
    let counts: [String: Int]
    let selected: String?
    let size: CGSize
    let onSelect: (String) -> Void
    let onCenterTap: () -> Void

    var body: some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Responsive radius that scales with window size but keeps nodes far apart
        let minDim = min(size.width, size.height)
        let radius = max(minDim * 0.32, 140)

        ZStack {
            ForEach(Array(collections.enumerated()), id: \.element) { index, name in
                let position = nodePosition(index: index, total: collections.count, center: center, radius: radius)
                ConnectionLine(from: center, to: position, isActive: selected == name)
            }

            CenterNode(isActive: selected != nil)
                .position(center)
                .onTapGesture { onCenterTap() }
                .help("Back to collections overview")

            ForEach(Array(collections.enumerated()), id: \.element) { index, name in
                let position = nodePosition(index: index, total: collections.count, center: center, radius: radius)
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
        // Add a bit of jitter or offset if there are too many nodes
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
            isActive ? Color.accentColor : Color.secondary.opacity(0.15),
            style: StrokeStyle(lineWidth: isActive ? 3 : 1, lineCap: .round)
        )
        .animation(.spring(response: 0.3), value: isActive)
    }
}

private struct CenterNode: View {
    var isActive: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(isActive ? 0.2 : 0.1))
                .frame(width: 120, height: 120)
                .blur(radius: 8)
                
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 90, height: 90)
                .overlay {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                }
            
            VStack(spacing: 4) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                Text("BrainDead")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .scaleEffect(isActive ? 0.9 : 1.0)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isActive)
    }
}

private struct CollectionNode: View {
    let name: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        let color = collectionColor(name)
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(isSelected ? 0.25 : 0.15))
                    .frame(width: 84, height: 84)
                
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 70, height: 70)
                    .overlay {
                        Circle()
                            .stroke(color.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 3 : 1)
                    }
                
                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(color)
                    Text("items")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(color.opacity(0.7))
                }
            }
            .shadow(color: color.opacity(isSelected ? 0.3 : 0), radius: 10)
            
            Text(collectionTitle(name))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(isSelected ? color.opacity(0.1) : .clear, in: Capsule())
        }
        .scaleEffect(isSelected ? 1.15 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSelected)
    }
}

@MainActor
private final class MemoryViewerModel: ObservableObject {
    @Published var items: [MemoryItem] = []
    @Published var collections: [String] = defaultCollectionOrder
    @Published var counts: [String: Int] = [:]
    @Published var isLoading = false
    @Published var isCreatingCollection = false
    @Published var errorMessage: String?

    private let client = MemoryClient()

    func refresh() async {
        isLoading = true
        errorMessage = nil
        do {
            async let fetchedMemory = client.fetchMemory(limit: 500)
            async let fetchedCollections = client.fetchCollections()
            let (fetched, serverCollections) = try await (fetchedMemory, fetchedCollections)
            items = fetched
            collections = orderedCollections(serverCollections, items: fetched)
            var tally: [String: Int] = [:]
            for item in fetched {
                tally[item.collection, default: 0] += 1
            }
            counts = tally
        } catch {
            errorMessage = "Could not load memory. Is the server running?"
            items = []
            collections = defaultCollectionOrder
            counts = [:]
        }
        isLoading = false
    }

    func createCollection(name: String) async -> String? {
        isCreatingCollection = true
        errorMessage = nil
        do {
            let result = try await client.createCollection(name: name)
            collections = orderedCollections(result.collections, items: items)
            isCreatingCollection = false
            return result.name
        } catch {
            errorMessage = error.localizedDescription
            isCreatingCollection = false
            return nil
        }
    }

    private func orderedCollections(_ names: [String], items: [MemoryItem]) -> [String] {
        var ordered: [String] = []
        for name in defaultCollectionOrder where names.contains(name) {
            ordered.append(name)
        }
        for name in names.sorted() where !ordered.contains(name) {
            ordered.append(name)
        }
        for item in items where !ordered.contains(item.collection) {
            ordered.append(item.collection)
        }
        return ordered
    }

}

private func collectionTitle(_ name: String) -> String {
    name.replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .capitalized
}

private func collectionColor(_ name: String) -> Color {
    if let color = collectionPalette[name] {
        return color
    }
    let colors: [Color] = [.cyan, .mint, .indigo, .pink, .teal, .red, .yellow]
    let value = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
    return colors[abs(value) % colors.count]
}
