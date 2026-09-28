import SwiftUI
import AppKit

/// Brings Tidy to the front on its very first launch, since it's a menu-bar
/// (LSUIElement) app with no Dock icon — without this, the welcome window
/// could open behind other windows and look like nothing happened. On every
/// later launch (including as a login item) it stays quiet, as a menu-bar
/// app should.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let completedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !completedOnboarding {
            NSApp.activate(ignoringOtherApps: true)
        }
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
    private let scheduler = Scheduler()

    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "sparkles") {
            MenuBarView()
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
