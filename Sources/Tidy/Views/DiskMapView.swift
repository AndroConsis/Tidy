import SwiftUI
import AppKit

@MainActor
final class DiskMapModel: ObservableObject {
    typealias Node = DiskMapModule.Node

    @Published var root: Node?
    @Published var overview: DiskMapModule.Overview?
    /// Breadcrumb from the Home folder down to the folder on screen.
    @Published var path: [Node] = []
    /// The tile the inspector describes; nil means the folder on screen.
    @Published var selected: Node?
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
                    self.selected = nil
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
            selected = nil
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
                self.selected = nil
                self.path.append(node)
            }
        }
    }

    func goUp(to index: Int?) {
        selected = nil
        if let index { path = Array(path.prefix(index + 1)) } else { path = [] }
    }

    /// Keeps the map honest after something inside it was cleaned: every
    /// folder above the removed path shrinks by what was freed.
    func didRemove(_ paths: [String], bytes: Int64) {
        guard let root, bytes > 0 else { return }
        func shrink(_ node: Node) {
            let prefix = node.url.path + "/"
            guard paths.contains(where: { $0.hasPrefix(prefix) || $0 == node.url.path }) else { return }
            node.size = max(node.size - bytes, 0)
            node.children?.removeAll { paths.contains($0.url.path) }
            node.children?.forEach(shrink)
        }
        shrink(root)
        objectWillChange.send()
    }
}

/// Neon palette for the map. Saturated, light colours that glow on the
/// console's near-black background.
enum Neon {
    static let cyan = Color(hex: 0x00E5FF)
    static let magenta = Color(hex: 0xFF2BD6)
    static let blue = Color(hex: 0x3D7BFF)
    static let lime = Color(hex: 0x7CFF6B)
    static let orange = Color(hex: 0xFF9F1C)
    static let violet = Color(hex: 0xA25BFF)
    static let ice = Color(hex: 0x9AF6FF)
    static let pink = Color(hex: 0xFF5C8A)
    static let energy = Color(hex: 0xFFC233)
    static let palette: [Color] = [cyan, magenta, blue, lime, orange, violet, ice, pink]

    static let background = LinearGradient(colors: [Color(hex: 0x03050C), Color(hex: 0x071028), Color(hex: 0x050816)],
                                           startPoint: .top, endPoint: .bottom)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// A soft two-layer glow in the given colour.
    func neonGlow(_ color: Color, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.85), radius: radius / 2).shadow(color: color.opacity(0.45), radius: radius)
    }
}

struct DiskMapView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: DiskMapModel
    let openSection: (Section_, SubTab?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TronBackground(animated: !reduceMotion)
            VStack(alignment: .leading, spacing: 14) {
                titleBar
                if let overview = model.overview { NeonStorageBar(overview: overview) }
                if let current = model.current {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            breadcrumb
                            ZStack {
                                TreemapView(node: current, selected: model.selected?.id, cleanableBytes: cleanableBytes(in:),
                                            animated: !reduceMotion,
                                            onSelect: { model.selected = $0 }, onOpen: model.open)
                                    .id(current.url)
                                if model.loadingFolder != nil {
                                    ScannerRings(caption: "MEASURING", animated: !reduceMotion).frame(width: 150, height: 150)
                                }
                            }
                        }
                        DiskMapInspector(node: model.selected ?? current, isCurrentFolder: model.selected == nil,
                                         items: cleanableItems(in: model.selected ?? current),
                                         onOpen: { model.open($0) },
                                         onClean: clean, onLargeFiles: { openSection(.largeFiles, nil) })
                            .frame(width: 270)
                    }
                } else {
                    emptyState
                }
            }
            .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Neon.cyan.opacity(0.25), lineWidth: 1))
        .padding(14)
        .environment(\.colorScheme, .dark)
        .navigationTitle("Disk Map")
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.grid.3x3.square").foregroundStyle(Neon.cyan).neonGlow(Neon.cyan, radius: 6)
            Text("DISK MAP").font(Neon.mono(13, .bold)).tracking(3).foregroundStyle(.white).neonGlow(Neon.cyan, radius: 4)
            Spacer()
            if model.root != nil {
                if model.isScanning {
                    Text("MEASURING · \(model.visitedCount.formatted())").font(Neon.mono(10)).foregroundStyle(Neon.cyan)
                } else {
                    Button("MEASURE AGAIN") { model.scan() }.buttonStyle(NeonButtonStyle(color: Neon.cyan, compact: true))
                }
            }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            crumb("HOME", isLast: model.path.isEmpty) { model.goUp(to: nil) }
            ForEach(Array(model.path.enumerated()), id: \.element.id) { index, node in
                Text("›").font(Neon.mono(11)).foregroundStyle(Neon.cyan.opacity(0.5))
                crumb(node.name.uppercased(), isLast: index == model.path.count - 1) { model.goUp(to: index) }
            }
            Spacer()
            if let current = model.current {
                Text(ByteCountFormatter.string(fromByteCount: current.size, countStyle: .file))
                    .font(Neon.mono(12, .semibold)).foregroundStyle(Neon.cyan)
            }
        }
    }

    private func crumb(_ title: String, isLast: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Neon.mono(11, isLast ? .bold : .regular))
                .foregroundStyle(isLast ? .white : Neon.cyan.opacity(0.75))
        }
        .buttonStyle(.plain)
        .disabled(isLast)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ScannerRings(caption: model.isScanning ? "\(model.visitedCount.formatted()) ITEMS" : "READY",
                         animated: model.isScanning && !reduceMotion)
                .frame(width: 190, height: 190)
            Text(model.isScanning ? "Measuring your Home folder…" : "See what's taking up space")
                .font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text("Tidy draws your folders to scale and shows what's safe to clean inside them. It reads sizes only.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center).frame(maxWidth: 380)
            if model.isScanning {
                Button("STOP") { model.cancel() }.buttonStyle(NeonButtonStyle(color: Neon.magenta))
            } else {
                Button("MEASURE MY HOME FOLDER") { model.scan() }.buttonStyle(NeonButtonStyle(color: Neon.cyan))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cleanableItems(in node: DiskMapModule.Node) -> [CleanableItem] {
        let prefix = node.url.path + "/"
        return state.result.all
            .filter { item in item.safety != .personal && item.sizeBytes > 0
                && item.paths.contains { $0 == node.url.path || $0.hasPrefix(prefix) } }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private func cleanableBytes(in node: DiskMapModule.Node) -> Int64 {
        cleanableItems(in: node).reduce(0) { $0 + $1.sizeBytes }
    }

    private func clean(_ items: [CleanableItem]) {
        for item in items {
            let before = state.result.all.contains { $0.id == item.id }
            state.clean(item)
            let removed = before && !state.result.all.contains { $0.id == item.id }
            if removed { model.didRemove(item.paths, bytes: item.sizeBytes) }
        }
    }
}

// MARK: - Console pieces

/// A receding neon grid floor with a horizon glow, drifting slowly towards
/// the viewer.
struct TronBackground: View {
    let animated: Bool

    var body: some View {
        ZStack {
            Neon.background
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    grid(phase: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2) / 2)
                }
            } else {
                grid(phase: 0)
            }
            RadialGradient(colors: [Neon.cyan.opacity(0.18), .clear], center: .bottom, startRadius: 10, endRadius: 520)
                .allowsHitTesting(false)
        }
    }

    private func grid(phase: Double) -> some View {
        Canvas { context, size in
            let horizon = size.height * 0.45
            let floor = size.height - horizon
            let color = Neon.cyan
            // Lines running away from the viewer, converging on the horizon.
            let vanishing = CGPoint(x: size.width / 2, y: horizon)
            for i in -14...14 {
                var line = Path()
                line.move(to: vanishing)
                line.addLine(to: CGPoint(x: size.width / 2 + CGFloat(i) * size.width / 9, y: size.height))
                context.stroke(line, with: .color(color.opacity(0.10)), lineWidth: 1)
            }
            // Cross lines, spaced by perspective, scrolling towards the viewer.
            for i in 0..<14 {
                let t = (Double(i) + phase) / 14
                let y = horizon + floor * CGFloat(t * t)
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(color.opacity(0.04 + 0.14 * t)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

struct NeonButtonStyle: ButtonStyle {
    var color: Color
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Neon.mono(compact ? 10 : 12, .bold))
            .tracking(1.5)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 10 : 18)
            .padding(.vertical, compact ? 5 : 9)
            .background(Capsule().fill(color.opacity(configuration.isPressed ? 0.35 : 0.16)))
            .overlay(Capsule().strokeBorder(color, lineWidth: 1.2))
            .neonGlow(color, radius: configuration.isPressed ? 10 : 6)
            .contentShape(Capsule())
    }
}

/// Concentric rotating rings shown while measuring.
struct ScannerRings: View {
    let caption: String
    let animated: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .trim(from: 0, to: [0.72, 0.5, 0.3][ring])
                    .stroke([Neon.cyan, Neon.magenta, Neon.ice][ring], style: StrokeStyle(lineWidth: [2.5, 1.5, 3][ring], lineCap: .round))
                    .padding(CGFloat(ring) * 18)
                    .rotationEffect(.degrees(spin ? (ring == 1 ? -360 : 360) : 0))
                    .animation(animated ? .linear(duration: [2.4, 3.6, 1.6][ring]).repeatForever(autoreverses: false) : .default, value: spin)
                    .neonGlow([Neon.cyan, Neon.magenta, Neon.ice][ring], radius: 6)
            }
            Text(caption).font(Neon.mono(10, .bold)).tracking(1.5).foregroundStyle(.white)
        }
        .onAppear { spin = animated }
        .onChange(of: animated) { spin = $0 }
    }
}

struct NeonStorageBar: View {
    let overview: DiskMapModule.Overview

    private var segments: [(String, Int64, Color)] {
        [("YOUR FILES", overview.home, Neon.violet), ("APPS", overview.apps, Neon.blue),
         ("MACOS & OTHER", overview.systemAndOther, Color(hex: 0x6B7A99)), ("FREE", overview.free, Neon.lime)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let total = max(segments.reduce(0) { $0 + $1.1 }, 1)
                HStack(spacing: 3) {
                    ForEach(segments, id: \.0) { segment in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(segment.2.opacity(0.75))
                            .frame(width: max(geo.size.width * CGFloat(segment.1) / CGFloat(total) - 3, 0))
                            .neonGlow(segment.2, radius: 5)
                    }
                }
            }
            .frame(height: 8)
            HStack(spacing: 18) {
                ForEach(segments, id: \.0) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.2).frame(width: 6, height: 6).neonGlow(segment.2, radius: 3)
                        Text(segment.0).font(Neon.mono(9)).foregroundStyle(.white.opacity(0.6))
                        Text(ByteCountFormatter.string(fromByteCount: segment.1, countStyle: .file))
                            .font(Neon.mono(10, .semibold)).foregroundStyle(.white)
                    }
                }
            }
        }
    }
}

// MARK: - Treemap

/// A squarified treemap: every tile's area is proportional to its size, and
/// tiles stay as close to square as possible so their labels fit.
struct TreemapView: View {
    let node: DiskMapModule.Node
    let selected: URL?
    let cleanableBytes: (DiskMapModule.Node) -> Int64
    let animated: Bool
    let onSelect: (DiskMapModule.Node) -> Void
    let onOpen: (DiskMapModule.Node) -> Void

    @State private var appeared = false
    @State private var tilt = CGSize.zero

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
                 color: Neon.palette[index % Neon.palette.count])
        }
        if node.otherSize > 0 {
            tiles.append(Tile(id: "other", node: nil, name: "\(node.otherCount) smaller",
                              size: node.otherSize, color: Color(hex: 0x6B7A99)))
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
                    NeonTile(name: tile.name, size: tile.size, color: tile.color,
                             isFolder: tile.node?.isDirectory == true,
                             isSelected: tile.node != nil && tile.node?.url == selected,
                             cleanableBytes: tile.node.map(cleanableBytes) ?? 0,
                             rect: rect, animated: animated)
                        .frame(width: max(rect.width - 4, 0), height: max(rect.height - 4, 0))
                        .offset(x: rect.minX, y: rect.minY)
                        .scaleEffect(appeared ? 1 : 0.6, anchor: .center)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75).delay(animated ? Double(index) * 0.03 : 0), value: appeared)
                        .onTapGesture(count: 2) { if let n = tile.node { onOpen(n) } }
                        .onTapGesture { if let n = tile.node { onSelect(n) } }
                        .contextMenu {
                            if let n = tile.node {
                                if n.isDirectory { Button("Open") { onOpen(n) } }
                                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([n.url]) }
                            }
                        }
                }
            }
            .overlay { if animated { Scanline() } }
            .onContinuousHover { phase in
                guard animated else { return }
                switch phase {
                case .active(let point):
                    tilt = CGSize(width: (point.x / max(geo.size.width, 1) - 0.5) * 5,
                                  height: (0.5 - point.y / max(geo.size.height, 1)) * 4)
                case .ended:
                    tilt = .zero
                }
            }
        }
        // Rises out of the grid floor on arrival, then leans gently towards the pointer.
        .rotation3DEffect(.degrees(appeared ? Double(tilt.height) : 28), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.6)
        .rotation3DEffect(.degrees(Double(tilt.width)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .animation(.easeOut(duration: 0.6), value: appeared)
        .animation(.easeOut(duration: 0.25), value: tilt)
        .frame(minHeight: 260)
        .onAppear { appeared = true }
    }

    struct NeonTile: View {
        let name: String
        let size: Int64
        let color: Color
        let isFolder: Bool
        let isSelected: Bool
        let cleanableBytes: Int64
        let rect: CGRect
        let animated: Bool
        @State private var hovering = false
        @State private var pulse = false

        private var lit: Bool { hovering || isSelected }
        private var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
            ZStack(alignment: .topLeading) {
                shape.fill(LinearGradient(colors: [color.opacity(lit ? 0.34 : 0.22), color.opacity(0.05)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                shape.strokeBorder(isSelected ? .white : color.opacity(lit ? 1 : 0.8), lineWidth: isSelected ? 2 : 1.2)
                    .neonGlow(color, radius: lit ? 12 : 5)
                if cleanableBytes > 0 {
                    shape.strokeBorder(Neon.energy, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4], dashPhase: pulse ? 20 : 0))
                        .opacity(pulse ? 0.95 : 0.45)
                        .neonGlow(Neon.energy, radius: 6)
                        .padding(3)
                }
                if rect.width > 70 && rect.height > 34 {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Image(systemName: isFolder ? "folder.fill" : "doc.fill").font(.system(size: 9))
                                .foregroundStyle(color)
                            Text(name.uppercased()).font(Neon.mono(rect.width > 150 ? 11 : 9, .bold)).lineLimit(1)
                                .foregroundStyle(.white)
                        }
                        Text(sizeText).font(Neon.mono(rect.width > 150 ? 11 : 9)).foregroundStyle(color)
                        if cleanableBytes > 0 && rect.height > 70 && rect.width > 120 {
                            Label(ByteCountFormatter.string(fromByteCount: cleanableBytes, countStyle: .file) + " CLEANABLE",
                                  systemImage: "bolt.fill")
                                .font(Neon.mono(9, .bold))
                                .foregroundStyle(Neon.energy)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .overlay(Capsule().strokeBorder(Neon.energy.opacity(0.8), lineWidth: 1))
                                .neonGlow(Neon.energy, radius: 4)
                                .padding(.top, 2)
                        }
                    }
                    .shadow(color: color.opacity(0.7), radius: 3)
                    .padding(8)
                }
            }
            .contentShape(shape)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.15), value: hovering)
            .onAppear {
                guard animated, cleanableBytes > 0 else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
            }
            .help("\(name) — \(sizeText)\(cleanableBytes > 0 ? " · \(ByteCountFormatter.string(fromByteCount: cleanableBytes, countStyle: .file)) cleanable" : "")")
            .accessibilityElement()
            .accessibilityLabel("\(name), \(sizeText)")
            .accessibilityAddTraits(.isButton)
        }
    }

    /// A band of light sweeping down the map every few seconds.
    struct Scanline: View {
        var body: some View {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) / 5
                    LinearGradient(colors: [.clear, Neon.cyan.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 70)
                        .offset(y: CGFloat(phase) * (geo.size.height + 140) - 70)
                        .blendMode(.plusLighter)
                }
            }
            .clipped()
            .allowsHitTesting(false)
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

// MARK: - Inspector

/// Describes the selected tile (or the folder on screen) and lists what
/// Tidy can clean inside it, so the user can clean right from the map.
struct DiskMapInspector: View {
    let node: DiskMapModule.Node
    let isCurrentFolder: Bool
    let items: [CleanableItem]
    let onOpen: (DiskMapModule.Node) -> Void
    let onClean: ([CleanableItem]) -> Void
    let onLargeFiles: () -> Void

    private var safeItems: [CleanableItem] { items.filter { $0.safety == .regenerable } }
    private var total: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isCurrentFolder ? "THIS FOLDER" : "SELECTED").font(Neon.mono(9, .bold)).tracking(2).foregroundStyle(Neon.cyan.opacity(0.7))
                Text(node.name).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(.white).lineLimit(2)
                Text(ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file))
                    .font(Neon.mono(22, .bold)).foregroundStyle(Neon.cyan).neonGlow(Neon.cyan, radius: 6)
                HStack(spacing: 8) {
                    if node.isDirectory && !isCurrentFolder {
                        Button("OPEN") { onOpen(node) }.buttonStyle(NeonButtonStyle(color: Neon.cyan, compact: true))
                    }
                    Button("FINDER") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                        .buttonStyle(NeonButtonStyle(color: Neon.blue, compact: true))
                }
                .padding(.top, 4)
            }

            Rectangle().fill(Neon.cyan.opacity(0.2)).frame(height: 1)

            if items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("NOTHING TO CLEAN HERE").font(Neon.mono(10, .bold)).foregroundStyle(.white.opacity(0.7))
                    Text("Tidy found no caches or junk in this folder. Big personal files? Look for them in Large Files.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                    Button("FIND LARGE FILES", action: onLargeFiles).buttonStyle(NeonButtonStyle(color: Neon.violet, compact: true))
                }
                Spacer(minLength: 0)
            } else {
                HStack {
                    Label("\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)) CLEANABLE", systemImage: "bolt.fill")
                        .font(Neon.mono(10, .bold)).foregroundStyle(Neon.energy).neonGlow(Neon.energy, radius: 4)
                    Spacer()
                }
                if !safeItems.isEmpty {
                    Button("CLEAN SAFE · \(ByteCountFormatter.string(fromByteCount: safeItems.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))") {
                        onClean(safeItems)
                    }
                    .buttonStyle(NeonButtonStyle(color: Neon.lime, compact: true))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            InspectorItemRow(item: item) { onClean([item]) }
                        }
                    }
                }
                Text("Review items are yours to judge: each one says what removing it costs.")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.45)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Neon.cyan.opacity(0.3), lineWidth: 1))
    }
}

struct InspectorItemRow: View {
    let item: CleanableItem
    let onClean: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(item.name).font(.system(size: 12, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
                Text(item.sizeString).font(Neon.mono(10, .semibold)).foregroundStyle(.white)
            }
            Text(item.explanation).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55)).lineLimit(2)
            HStack {
                SafetyBadge(safety: item.safety)
                Spacer()
                switch item.action {
                case .trash, .command:
                    Button("CLEAN", action: onClean)
                        .buttonStyle(NeonButtonStyle(color: item.safety == .regenerable ? Neon.lime : Neon.energy, compact: true))
                case .reveal:
                    Button("FINDER", action: onClean).buttonStyle(NeonButtonStyle(color: Neon.blue, compact: true))
                case .launchApp:
                    Button("UNINSTALLER", action: onClean).buttonStyle(NeonButtonStyle(color: Neon.energy, compact: true))
                case .guide:
                    EmptyView()
                }
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
