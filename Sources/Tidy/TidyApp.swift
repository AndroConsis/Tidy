import SwiftUI
import AppKit
import UserNotifications

/// Brings Tidy to the front on its very first launch, since it's a menu-bar
/// (LSUIElement) app with no Dock icon — without this, the welcome window
/// could open behind other windows and look like nothing happened. On every
/// later launch (including as a login item) it stays quiet, as a menu-bar
/// app should.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Wired up from TidyApp's body, since only a SwiftUI environment (not
    /// this AppKit delegate) can ask a declarative `Window` scene to open.
    /// Needed because a singleton `Window` scene that the user closed in a
    /// past session does NOT reopen itself automatically on the next launch —
    /// a first-run user who closes the welcome window (an easy thing to do,
    /// thinking it quits a menu-bar app) would otherwise be stuck: no Dock
    /// icon, onboarding never finishes, and the scanner — gated on
    /// onboarding completing — never runs again.
    var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        #if DEBUG
        if ScreenshotRenderer.runIfRequested() { return }
        #endif

        let completedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        guard !completedOnboarding else { return }
        NSApp.activate(ignoringOtherApps: true)
        ensureMainWindowVisible(attemptsRemaining: 15)
    }

    /// For an LSUIElement app, SwiftUI never auto-opens a declared `Window`
    /// scene at launch — confirmed by instrumenting a real launch: NSApp.windows
    /// stays at 1 (just the MenuBarExtra's own hidden popover window) the
    /// entire time, however long we wait. openWindow(id:) is what actually
    /// creates it, so on first launch (or if the user closed it last session)
    /// this always has to fall back to that explicit call — the brief poll
    /// beforehand only covers the (currently unobserved, but cheap to guard
    /// against) case of a slower scene-graph startup.
    private func ensureMainWindowVisible(attemptsRemaining: Int, calledOpenMainWindow: Bool = false) {
        if let window = mainWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        guard attemptsRemaining > 0 else {
            // SwiftUI never auto-opens this "Window" scene for an LSUIElement
            // app, so it's never in NSApp.windows on its own — openWindow(id:)
            // is what actually creates it. That creation is itself
            // asynchronous, so once fired, keep polling (a second, shorter
            // round) until it shows up and can be ordered front; calling
            // openMainWindow() more than once here would just open duplicates.
            if !calledOpenMainWindow {
                openMainWindow?()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.ensureMainWindowVisible(attemptsRemaining: 20, calledOpenMainWindow: true)
                }
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.ensureMainWindowVisible(attemptsRemaining: attemptsRemaining - 1, calledOpenMainWindow: calledOpenMainWindow)
        }
    }

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" || $0.title == "Tidy" }
    }

    /// LSUIElement apps have no Dock icon, so there's no standard way for the
    /// user to re-raise a window that's fallen behind another app — clicking
    /// the menu bar icon or "Open Tidy…" only asks the window to *open*,
    /// which macOS treats as a no-op if it's already open, even when it's
    /// buried. Explicitly re-activating and ordering it front each time
    /// closes that gap.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        bringMainWindowToFront()
        return true
    }

    func bringMainWindowToFront() {
        NSApp.activate(ignoringOtherApps: true)
        ensureMainWindowVisible(attemptsRemaining: 5)
    }

    /// Without this, macOS silently drops any notification Tidy tries to
    /// show while it's the frontmost app (e.g. the main window is open) —
    /// the default UserNotifications behavior is to suppress foreground
    /// notifications unless a delegate opts back in.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

struct RootView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        Group {
            if state.hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
    }
}

@main
struct TidyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow
    private let scheduler = Scheduler()

    var body: some Scene {
        // Body re-evaluates whenever `state` changes, but this just
        // overwrites the same closure each time — harmless, and it's the
        // only way to hand SwiftUI's openWindow action to the AppDelegate,
        // which has no environment of its own.
        let _ = { appDelegate.openMainWindow = { openWindow(id: "main") } }()

        MenuBarExtra("Tidy", systemImage: "sparkles") {
            MenuBarView(openMainWindow: { appDelegate.bringMainWindowToFront() })
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("Tidy", id: "main") {
            RootView()
                .environmentObject(state)
                .task {
                    scheduler.start(with: state)
                }
        }
        .defaultSize(width: 780, height: 520)
    }
}
