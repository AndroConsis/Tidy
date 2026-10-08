import SwiftUI
import AppKit

/// Laid out like System Settings: one centred column of grouped cards, each
/// row with a coloured icon tile, a title, a short explanation, and its
/// control right-aligned, so every row lines up.
struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject private var folderAccess = FolderAccess.shared

    private let frequencies: [(String, Int)] = [("Daily", 1), ("Weekly", 7), ("Monthly", 30)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                SettingsGroup("Cleaning") {
                    SettingsRow(icon: "clock.arrow.circlepath", color: Theme.teal,
                                title: "Clean safe items automatically",
                                subtitle: "Only items marked Safe. Everything else waits for you.") {
                        Toggle("", isOn: $state.autoCleanEnabled).toggleStyle(.switch).labelsHidden()
                    }
                    if state.autoCleanEnabled {
                        SettingsDivider()
                        SettingsRow(icon: "calendar", color: Theme.violet, title: "How often",
                                    subtitle: lastAutoCleanText) {
                            Picker("", selection: $state.autoCleanFrequencyDays) {
                                ForEach(frequencies, id: \.1) { Text($0.0).tag($0.1) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 210)
                        }
                    }
                }

                SettingsGroup("General") {
                    SettingsRow(icon: "power", color: .blue, title: "Open Tidy at login",
                                subtitle: "Keeps Tidy in your menu bar.") {
                        Toggle("", isOn: $state.launchAtLogin).toggleStyle(.switch).labelsHidden()
                    }
                    SettingsDivider()
                    SettingsRow(icon: "house.fill", color: .green, title: "Home folder",
                                subtitle: folderAccess.hasHomeAccess ? "Granted. Used to find caches and junk." : "Not granted. Most scans need it.") {
                        accessButton(granted: folderAccess.hasHomeAccess) {
                            if folderAccess.requestHomeAccess() { Task { await state.scan() } }
                        }
                    }
                    SettingsDivider()
                    SettingsRow(icon: "square.grid.2x2.fill", color: .indigo, title: "Applications folder",
                                subtitle: folderAccess.hasApplicationsAccess ? "Granted. Used to remove apps you choose." : "Needed only to remove apps.") {
                        accessButton(granted: folderAccess.hasApplicationsAccess) {
                            folderAccess.requestApplicationsAccess()
                        }
                    }
                }

                SettingsGroup("Support") {
                    SettingsLinkRow(icon: "envelope.fill", color: .orange, title: "Send Feedback",
                                    subtitle: "Bugs, ideas, or something Tidy should clean.") { Feedback.sendFeedback() }
                    SettingsDivider()
                    SettingsLinkRow(icon: "star.fill", color: .yellow, title: "Rate Tidy",
                                    subtitle: "A rating on the App Store helps others find Tidy.") { Feedback.openWriteReview() }
                    SettingsDivider()
                    SettingsLinkRow(icon: "sparkles", color: Theme.violet, title: "Welcome Guide",
                                    subtitle: "See the introduction again.") { state.hasCompletedOnboarding = false }
                }

                SettingsGroup("How Tidy keeps you safe") {
                    SettingsSafetyRow(icon: "arrow.uturn.backward.circle.fill", color: Theme.teal, title: "Trash first",
                              text: "Removals go to the Trash, so Finder can put them back.")
                    SettingsDivider()
                    SettingsSafetyRow(icon: "hand.raised.fill", color: Theme.amber, title: "You decide",
                              text: "Only Safe items are ever cleaned without a click. Everything else waits for you.")
                    SettingsDivider()
                    SettingsSafetyRow(icon: "photo.fill", color: .pink, title: "Personal data stays put",
                              text: "Photos, Mail and Messages are never cleaned. Tidy points you to the right setting.")
                    SettingsDivider()
                    SettingsSafetyRow(icon: "magnifyingglass", color: .cyan, title: "Searches only when asked",
                              text: "Large Files and Disk Map look through your Home folder only when you start them.")
                    SettingsDivider()
                    SettingsSafetyRow(icon: "lock.fill", color: .gray, title: "No admin password",
                              text: "Anything owned by macOS is shown in Finder for you to remove.")
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 660)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tidy").font(.system(size: 20, weight: .bold, design: .rounded))
                Text("Version \(Feedback.appVersion)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var lastAutoCleanText: String {
        if let last = state.lastAutoCleanDate {
            return "Last ran \(last.formatted(.relative(presentation: .named)))."
        }
        return "Runs at the next scheduled check."
    }

    @ViewBuilder
    private func accessButton(granted: Bool, action: @escaping () -> Void) -> some View {
        if granted {
            Button("Change…", action: action).controlSize(.small)
        } else {
            Button("Grant Access…", action: action).controlSize(.small).buttonStyle(.borderedProminent).tint(Theme.violet)
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().padding(.leading, 54)
    }
}

/// The rounded-square coloured icon System Settings uses for each row.
struct IconTile: View {
    let icon: String
    let color: Color
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
    }
}

struct SettingsRow<Trailing: View>: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            IconTile(icon: icon, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// A whole-row button with a chevron, like a link in System Settings.
struct SettingsLinkRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            SettingsRow(icon: icon, color: color, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .background(Color.primary.opacity(hovering ? 0.04 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct SettingsSafetyRow: View {
    let icon: String
    let color: Color
    let title: String
    let text: String

    var body: some View {
        SettingsRow(icon: icon, color: color, title: title, subtitle: text) { EmptyView() }
    }
}
