import SwiftUI

@main
struct TidyApp: App {
    @StateObject private var state = AppState()
    private let scheduler = Scheduler()

    init() {
        Notifier.requestAuthorization()
    }

    var body: some Scene {
        MenuBarExtra("Tidy", systemImage: "sparkles") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        Window("Tidy", id: "main") {
            ContentView()
                .environmentObject(state)
                .task {
                    scheduler.start(with: state)
                }
        }
        .defaultSize(width: 780, height: 520)
    }
}
