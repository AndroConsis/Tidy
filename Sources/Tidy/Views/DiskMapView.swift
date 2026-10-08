import SwiftUI
import AppKit

@MainActor
final class DiskMapModel: ObservableObject {
    typealias Node = DiskMapModule.Node

    @Published var root: Node?
    @Published var overview: DiskMapModule.Overview?
    /// Breadcrumb from the Home folder down to the folder on screen.
    @Published var path: [Node] = []
    @Published var isScanning = false
    @Published var loadingFolder: URL?
    @Published var visitedCount = 0
    private var cancelled = false

    var current: Node? { path.last ?? root }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        cancelled = false
        visitedCount = 0
        Task.detached(priority: .utility) { [weak self] in
            let root = DiskMapModule.measure(FSUtil.home, levels: 2,
                isCancelled: { [weak self] in
                    guard let self else { return true }
                    return DispatchQueue.main.sync { self.cancelled }
                },
                progress: { [weak self] count in
                    DispatchQueue.main.async { self?.visitedCount = count }
                })
            let overview = DiskMapModule.overview(homeSize: root.size)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !self.cancelled {
                    self.root = root
                    self.overview = overview
                    self.path = []
                }
                self.isScanning = false
            }
        }
    }

    func cancel() { cancelled = true }

    /// Opens a folder, measuring its contents first if that hasn't happened.
    func open(_ node: Node) {
        guard node.isDirectory, loadingFolder == nil else { return }
        if node.children != nil {
            path.append(node)
            return
        }
        loadingFolder = node.url
        let url = node.url
        Task.detached(priority: .userInitiated) { [weak self] in
            let measured = DiskMapModule.measure(url, levels: 2)
            await MainActor.run { [weak self] in
                guard let self else { return }
                node.children = measured.children
                node.otherSize = measured.otherSize
                node.otherCount = measured.otherCount
                self.loadingFolder = nil
                self.path.append(node)
            }
        }
    }

    func goUp(to index: Int?) {
        if let index { path = Array(path.prefix(index + 1)) } else { path = [] }
    }
}

struct DiskMapView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: DiskMapModel
    let openSection: (Section_) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let overview = model.overview {
                StorageOverviewBar(overview: overview)
            }
            if let current = model.current {
                breadcrumb
                ZStack {
                    TreemapView(node: current, cleanable: cleanable(in:), onOpen: model.open, onReview: review)
                    if model.loadingFolder != nil {
                        ProgressView().controlSize(.large)
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text("Click a folder to look inside. Amber labels show what Tidy can already clean there. Other apps' private data (Containers) isn't measured.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                emptyState
            }
        }
        .padding(20)
        .navigationTitle("Disk Map")
        .toolbar {
            ToolbarItem {
                if model.root != nil && !model.isScanning {
                    Button { model.scan() } label: { Label("Measure Again", systemImage: "chart.bar.doc.horizontal") }
                        .help("Measure your Home folder again")
                }
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Button("Home") { model.goUp(to: nil) }
                .buttonStyle(.plain)
                .foregroundStyle(model.path.isEmpty ? .primary : Theme.violet)
            ForEach(Array(model.path.enumerated()), id: \.element.id) { index, node in
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                Button(node.name) { model.goUp(to: index) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == model.path.count - 1 ? .primary : Theme.violet)
            }
            Spacer()
            if let current = model.current {
                Text(ByteCountFormatter.string(fromByteCount: current.size, countStyle: .file))
                    .font(.system(size: 13, weight: .semibold))
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([current.url])
                } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
            }
        }
        .font(.system(size: 13, weight: .medium))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accentGradient)
            Text("See what's taking up space").font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Tidy measures the folders in your Home folder and draws them to scale, so the biggest ones stand out. It reads sizes only and changes nothing.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if model.isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Measured \(model.visitedCount.formatted()) items…").font(.system(size: 12)).foregroundStyle(.secondary)
                    Button("Stop") { model.cancel() }
                }
            } else {
                Button {
                    model.scan()
                } label: {
                    Label("Measure My Home Folder", systemImage: "chart.bar.doc.horizontal")
                }
                .buttonStyle(.gradientProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Bytes Tidy's own scan found inside a folder, and the section to see them in.
    private func cleanable(in node: DiskMapModule.Node) -> (bytes: Int64, section: Section_?) {
        let prefix = node.url.path.hasSuffix("/") ? node.url.path : node.url.path + "/"
        var bytesBySection: [Section_: Int64] = [:]
        for item in state.result.all where item.safety != .personal {
            guard item.paths.contains(where: { $0 == node.url.path || $0.hasPrefix(prefix) }) else { continue }
            bytesBySection[Section_.forCategory(item.category), default: 0] += item.sizeBytes
        }
        let total = bytesBySection.values.reduce(0, +)
        return (total, bytesBySection.max { $0.value < $1.value }?.key)
    }

    private func review(_ node: DiskMapModule.Node) {
        if let section = cleanable(in: node).section { openSection(section) }
    }
}

struct StorageOverviewBar: View {
    let overview: DiskMapModule.Overview

    private var segments: [(String, Int64, Color)] {
        [("Your files", overview.home, Theme.violet),
         ("Apps", overview.apps, .blue),
         ("macOS & other", overview.systemAndOther, .gray),
         ("Free", overview.free, Theme.teal)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
                HStack(spacing: 2) {
                    ForEach(segments, id: \.0) { segment in
                        Rectangle().fill(segment.2.gradient)
                            .frame(width: max(geo.size.width * CGFloat(segment.1) / CGFloat(total) - 2, 0))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(height: 14)
            HStack(spacing: 16) {
                ForEach(segments, id: \.0) { Legend(color: $0.2, label: $0.0, value: $0.1) }
            }
        }
        .padding(14)
        .background(Theme.cardBackground())
    }
}

/// A squarified treemap: every tile's area is proportional to its size, and
/// tiles stay as close to square as possible so their labels fit.
struct TreemapView: View {
    let node: DiskMapModule.Node
    let cleanable: (DiskMapModule.Node) -> (bytes: Int64, section: Section_?)
    let onOpen: (DiskMapModule.Node) -> Void
    let onReview: (DiskMapModule.Node) -> Void

    static let palette: [Color] = [Theme.violet, Theme.teal, .blue, .pink, .orange, .green, .indigo, .cyan, .purple, .mint, .brown, Theme.coral]

    private struct Tile: Identifiable {
        let id: String
        let node: DiskMapModule.Node?   // nil for the pooled "other" tile
        let name: String
        let size: Int64
        let color: Color
    }

    private var tiles: [Tile] {
        var tiles = (node.children ?? []).enumerated().map { index, child in
            Tile(id: child.url.path, node: child, name: child.name, size: child.size,
                 color: Self.palette[index % Self.palette.count])
        }
        if node.otherSize > 0 {
            tiles.append(Tile(id: "other", node: nil, name: "\(node.otherCount) smaller item\(node.otherCount == 1 ? "" : "s")",
                              size: node.otherSize, color: .gray))
        }
        return tiles
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = tiles
            let rects = Self.squarify(tiles.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                    let rect = rects[index]
                    TileView(name: tile.name, size: tile.size, color: tile.color,
                             isFolder: tile.node?.isDirectory == true,
                             cleanableBytes: tile.node.map { cleanable($0).bytes } ?? 0,
                             rect: rect)
                        .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
                        .offset(x: rect.minX, y: rect.minY)
                        .onTapGesture { if let n = tile.node { onOpen(n) } }
                        .contextMenu {
                            if let n = tile.node {
                                if n.isDirectory { Button("Open") { onOpen(n) } }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
                                if cleanable(n).bytes > 0 { Button("Review What Tidy Can Clean") { onReview(n) } }
                            }
                        }
                }
            }
        }
        .frame(minHeight: 260)
        .animation(.easeInOut(duration: 0.25), value: node.url)
    }

    struct TileView: View {
        let name: String
        let size: Int64
        let color: Color
        let isFolder: Bool
        let cleanableBytes: Int64
        let rect: CGRect
        @State private var hovering = false

        var body: some View {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(isFolder ? 0.85 : 0.6).gradient)
                .overlay(alignment: .topLeading) {
                    if rect.width > 64 && rect.height > 30 {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: isFolder ? "folder.fill" : "doc.fill").font(.system(size: 9))
                                Text(name).font(.system(size: rect.width > 140 ? 12 : 10, weight: .semibold)).lineLimit(1)
                            }
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.system(size: rect.width > 140 ? 11 : 9))
                                .opacity(0.85)
                            if cleanableBytes > 0 && rect.height > 64 && rect.width > 110 {
                                Text("\(ByteCountFormatter.string(fromByteCount: cleanableBytes, countStyle: .file)) cleanable")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.amber, in: Capsule())
                                    .foregroundStyle(.black.opacity(0.8))
                                    .padding(.top, 2)
                            }
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(7)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.9 : 0), lineWidth: 2)
                )
                .onHover { hovering = $0 }
                .help("\(name) — \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                .accessibilityElement()
                .accessibilityLabel("\(name), \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                .accessibilityAddTraits(isFolder ? .isButton : [])
        }
    }

    static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var remaining = rect
        var start = 0

        func worst(_ row: ArraySlice<Double>, _ side: Double) -> Double {
            let sum = row.reduce(0, +)
            guard let maxA = row.max(), let minA = row.min(), sum > 0, minA > 0 else { return .infinity }
            return max(side * side * maxA / (sum * sum), (sum * sum) / (side * side * minA))
        }

        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var best = worst(areas[start..<end], side)
            while end < areas.count {
                let next = worst(areas[start...end], side)
                if next > best { break }
                best = next
                end += 1
            }
            let rowArea = areas[start..<end].reduce(0, +)
            if remaining.width >= remaining.height {
                let width = CGFloat(rowArea) / remaining.height
                var y = remaining.minY
                for i in start..<end {
                    let height = CGFloat(areas[i]) / width
                    result[i] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                    y += height
                }
                remaining = CGRect(x: remaining.minX + width, y: remaining.minY, width: remaining.width - width, height: remaining.height)
            } else {
                let height = CGFloat(rowArea) / remaining.width
                var x = remaining.minX
                for i in start..<end {
                    let width = CGFloat(areas[i]) / height
                    result[i] = CGRect(x: x, y: remaining.minY, width: width, height: height)
                    x += width
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: remaining.height - height)
            }
            start = end
        }
        return result
    }
}
