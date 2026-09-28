import SwiftUI
import AppKit

struct ItemRowView: View {
    let item: CleanableItem
    let onClean: (CleanableItem) -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name).font(.system(size: 13, weight: .medium))
                    SafetyBadge(safety: item.safety)
                }
                Text(item.path.isEmpty ? item.category.rawValue : item.path)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.explanation)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                if item.sizeBytes > 0 {
                    Text(item.sizeString).font(.system(size: 13, weight: .semibold))
                }
                actionButton
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch item.action {
        case .trash, .command:
            Button("Clean") { onClean(item) }
                .controlSize(.small)
                .tint(Theme.teal)
        case .privilegedShell:
            Button {
                onClean(item)
            } label: {
                Label("Delete…", systemImage: "lock.fill")
            }
            .controlSize(.small)
            .tint(Theme.amber)
            .help("Asks for your admin password via macOS's own prompt.")
        case .launchApp:
            Button("Open Uninstaller") { onClean(item) }
                .controlSize(.small)
                .tint(Theme.amber)
        case .guide(let urlString):
            if let url = URL(string: urlString), !urlString.isEmpty {
                Button("Open Settings") { NSWorkspace.shared.open(url) }
                    .controlSize(.small)
            }
        }
    }
}

struct SafetyBadge: View {
    let safety: Safety
    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.4)
            .padding(.horizontal, 7).padding(.vertical, 2.5)
            .background(color.opacity(0.16))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
    private var label: String {
        switch safety {
        case .regenerable: return "SAFE"
        case .review: return "REVIEW"
        case .personal: return "MANUAL"
        }
    }
    private var color: Color { Theme.safetyColor(safety) }
}
