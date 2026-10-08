import SwiftUI
import AppKit
import UserNotifications

/// First-run welcome flow. Shown once, the first time someone opens Tidy —
/// gated by AppState.hasCompletedOnboarding. Explains what the app does,
/// how it stays safe, and asks for the permissions it actually needs
/// (contextually, not blind at launch), before handing off to the real app.
struct OnboardingView: View {
    @EnvironmentObject var state: AppState
    @State private var step: Step = .welcome

    enum Step: Int, CaseIterable {
        case welcome, safety, permissions, finish
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { s in
                    Capsule()
                        .fill(s == step ? Theme.violet : Color.primary.opacity(0.12))
                        .frame(width: s == step ? 20 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: step)
                }
            }
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep { advance() }
        case .safety: SafetyStep { advance() }
        case .permissions: PermissionsStep { advance() }
        case .finish: FinishStep { finish() }
        }
    }

    private func advance() {
        withAnimation { step = Step(rawValue: step.rawValue + 1) ?? .finish }
    }

    private func finish() {
        state.hasCompletedOnboarding = true
        // Scheduler already kicked off a scan on launch; if it's somehow not
        // running yet (e.g. permissions were just granted), make sure one starts.
        if !state.isScanning { Task { await state.scan() } }
    }
}

// MARK: - Step 1

private struct WelcomeStep: View {
    let onNext: () -> Void
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(Theme.accentGradient)
            Text("Welcome to Tidy").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Tidy finds stale Xcode data, developer caches, forgotten installers, and apps you no longer use — and helps you clear them safely.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            Spacer()
            Button("Get Started") { onNext() }
                .buttonStyle(.gradientProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}

// MARK: - Step 2

private struct SafetyStep: View {
    let onNext: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How Tidy stays safe").font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            VStack(spacing: 14) {
                SafetyRow(safety: .regenerable, text: "Caches and build data a tool rebuilds on its own. \"Clean all safe items\" and scheduled auto-clean only ever touch these.")
                SafetyRow(safety: .review, text: "Probably fine to remove, but Tidy always asks first — a single click, never automatic.")
                SafetyRow(safety: .personal, text: "Tidy never deletes this itself. It only explains the right, supported way to free the space (like Photos' \"Optimize Mac Storage\").")
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("Every removal defaults to the Trash — Finder's \u{201C}Put Back\u{201D} restores it.")
                bullet("Automatic scans only check known cache and build locations. Large Files and Disk Map search your Home folder only when you ask.")
                bullet("Every action is logged in Overview \u{2192} Recent Activity.")
            }
            .padding(.top, 4)

            Spacer()
            HStack {
                Spacer()
                Button("Continue") { onNext() }
                    .buttonStyle(.gradientProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Theme.violet.opacity(0.5)).frame(width: 5, height: 5).padding(.top, 5)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

private struct SafetyRow: View {
    let safety: Safety
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SafetyBadge(safety: safety).frame(width: 62, alignment: .leading)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Theme.cardBackground(cornerRadius: 10))
    }
}

// MARK: - Step 3

private struct PermissionsStep: View {
    let onNext: () -> Void
    @ObservedObject private var folderAccess = FolderAccess.shared
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A couple of permissions").font(.system(size: 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
            Text("Asked for here, once, rather than as a surprise later.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)

            PermissionRow(
                icon: "folder.badge.gearshape",
                title: "Home folder",
                detail: folderAccess.hasHomeAccess
                    ? "Granted — Tidy can look at the caches and build data in your Home folder."
                    : "Needed for almost everything Tidy finds (Xcode data, developer and app caches). macOS asks you to confirm by choosing the folder — it's already selected, just click Grant Access.",
                granted: folderAccess.hasHomeAccess,
                actionTitle: folderAccess.hasHomeAccess ? "Granted" : "Choose…"
            ) {
                folderAccess.requestHomeAccess()
            }

            PermissionRow(
                icon: "bell.badge",
                title: "Notifications",
                detail: notificationStatus == .authorized
                    ? "Granted — Tidy will let you know when space is worth reclaiming."
                    : "Lets Tidy notify you when it finds real space to reclaim, or finishes a scheduled clean.",
                granted: notificationStatus == .authorized,
                actionTitle: notificationStatus == .authorized ? "Granted" : "Allow"
            ) {
                Notifier.requestAuthorization { _ in refreshNotificationStatus() }
            }

            Spacer()
            HStack {
                Spacer()
                Button("Continue") { onNext() }
                    .buttonStyle(.gradientProminent)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .onAppear { refreshNotificationStatus() }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notificationStatus = settings.authorizationStatus }
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(granted ? Theme.teal : Theme.violet)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(actionTitle) { action() }
                .controlSize(.small)
                .disabled(granted)
        }
        .padding(12)
        .background(Theme.cardBackground(cornerRadius: 10))
    }
}

// MARK: - Step 4

private struct FinishStep: View {
    let onFinish: () -> Void
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentGradient)
            Text("You're all set").font(.system(size: 24, weight: .bold, design: .rounded))
            Text("Tidy lives in your menu bar (look for \u{2728}) and re-checks weekly while it's running. The full list of what it found appears after this first scan.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $state.launchAtLogin) {
                    Text("Open Tidy when I log in").font(.system(size: 12))
                }
                Toggle(isOn: $state.autoCleanEnabled) {
                    Text("Automatically clean SAFE items weekly").font(.system(size: 12))
                }
            }
            .toggleStyle(.switch)
            .padding(.top, 6)

            Spacer()
            Button("Start Scanning") { onFinish() }
                .buttonStyle(.gradientProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
