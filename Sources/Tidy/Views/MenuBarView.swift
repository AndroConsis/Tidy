import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.accentGradient)
                Text("Tidy").font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if state.autoCleanEnabled {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.teal)
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text("Free space").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: state.freeBytes, countStyle: .file))
                        .font(.system(size: 13, weight: .semibold))
                }
                HStack {
                    Text("Reclaimable").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: state.result.reclaimableBytes, countStyle: .file))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.amber)
                }
            }
            .padding(10)
            .background(Theme.cardBackground(cornerRadius: 10))

            Button {
                Task { await state.scan() }
            } label: {
                Label(state.isScanning ? "Scanning…" : "Scan Now", systemImage: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .disabled(state.isScanning)
            .buttonStyle(.plain)

            Button {
                state.cleanAllRegenerable()
            } label: {
                Label("Clean Safe Items", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.teal)
            }
            .disabled(state.result.safeAutoCleanBytes == 0)
            .buttonStyle(.plain)

            Divider()

            Button("Open Tidy…") {
                // bringMainWindowToFront() creates the window via openWindow
                // if it doesn't exist yet, or just raises it if it's already
                // open but buried behind another app — single code path so
                // there's no race between two separate open attempts.
                (NSApp.delegate as? AppDelegate)?.bringMainWindowToFront()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))

            Button("Quit Tidy") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(width: 250)
    }
}
