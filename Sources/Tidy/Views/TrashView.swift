import SwiftUI
import AppKit

/// macOS lets only Finder look inside or empty the Trash: a sandboxed app
/// can't read it, and can't even ask Finder to open it. So Tidy explains
/// that and brings Finder forward, where Empty Trash is one shortcut away.
struct TrashView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accentGradient)
            Text("Empty the Trash in Finder").font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("macOS lets only Finder empty the Trash. Anything Tidy removes waits there, so you can still put it back.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button {
                NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                                   configuration: NSWorkspace.OpenConfiguration())
            } label: {
                Label("Open Finder", systemImage: "macwindow")
            }
            .buttonStyle(.gradientProminent)
            HStack(spacing: 6) {
                Text("Then press")
                KeyCap("⇧"); KeyCap("⌘"); KeyCap("⌫")
                Text("or choose Finder › Empty Trash.")
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
    }
}
