import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var folderAccess = FolderAccess.shared

    private let frequencies: [(String, Int)] = [
        ("Daily", 1), ("Weekly", 7), ("Monthly", 30)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Image(systemName: "clock.badge.checkmark")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accentGradient)
                        Text("Scheduled Cleaning").font(.system(size: 16, weight: .semibold, design: .rounded))
                    }

                    Toggle(isOn: $state.autoCleanEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically clean safe items")
                            Text("Only items marked SAFE — regenerable caches Tidy is certain about. REVIEW and MANUAL items always need your click, scheduled or not.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if state.autoCleanEnabled {
                        Picker("Frequency", selection: $state.autoCleanFrequencyDays) {
                            ForEach(frequencies, id: \.1) { label, days in
                                Text(label).tag(days)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)

                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.teal).font(.system(size: 12))
                            if let last = state.lastAutoCleanDate {
                                Text("Last auto-clean: \(last.formatted(.relative(presentation: .named)))")
                            } else {
                                Text("Hasn't run yet — happens on the next scheduled check.")
                            }
                        }
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Theme.cardBackground())

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.accentGradient)
                        Text("General").font(.system(size: 16, weight: .semibold, design: .rounded))
                    }
                    Toggle("Open Tidy when I log in", isOn: $state.launchAtLogin)
                        .toggleStyle(.switch)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Home folder access")
                            Text(folderAccess.hasHomeAccess
                                 ? "Granted. Tidy can scan caches and build data in your Home folder."
                                 : "Not granted — most scans can't run until you choose your Home folder.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(folderAccess.hasHomeAccess ? "Choose Again…" : "Grant Access…") {
                            if folderAccess.requestHomeAccess() { Task { await state.scan() } }
                        }
                    }
                }
                .padding(16)
                .background(Theme.cardBackground())

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("How Tidy stays safe").font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    bullet("Tidy only scans the fixed list of paths built into each module — never a free filesystem walk.")
                    bullet("Every removal defaults to the Trash (Finder \u{201C}Put Back\u{201D} restores it) and is logged in Overview \u{2192} Recent Activity.")
                    bullet("Photos, Mail, Messages and your Trash are never touched automatically — Tidy only points you at the right Settings toggle.")
                    bullet("Tidy never asks for your admin password. Anything owned by macOS is shown in Finder for you to remove yourself.")
                }
                .padding(16)
                .background(Theme.cardBackground())

                Button("Replay Welcome Guide…") {
                    state.hasCompletedOnboarding = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Settings")
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.violet.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}
