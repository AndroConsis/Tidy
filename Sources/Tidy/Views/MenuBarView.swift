import SwiftUI
import AppKit

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    /// Passed in rather than looked up via `NSApp.delegate`: with
    /// @NSApplicationDelegateAdaptor, NSApp.delegate is SwiftUI's own wrapper,
    /// so casting it to Tidy's AppDelegate always fails.
    let openMainWindow: () -> Void

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
                openMainWindow()
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
