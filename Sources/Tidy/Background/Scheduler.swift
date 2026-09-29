import Foundation
import ServiceManagement

/// Runs a scan on launch, then again once a week (or immediately if free
/// space drops below 10%) while the app is running. Also registers Tidy
/// as a login item via SMAppService so the weekly check happens even if
/// the user doesn't open the app themselves.
@MainActor
final class Scheduler {
    private var timer: Timer?
    private weak var appState: AppState?
    private let weekInterval: TimeInterval = 7 * 24 * 60 * 60
    private let checkInterval: TimeInterval = 60 * 60 // check conditions hourly

    func start(with appState: AppState) {
        self.appState = appState
        // Onboarding owns the first scan (it runs once permissions have been
        // requested, in the Finish step). Scanning any earlier than that means
        // modules like InstallersModule hit Desktop/Downloads before the user
        // has even reached the permissions step, so macOS's folder-access
        // prompt appears out of nowhere on top of the welcome screen.
        if appState.hasCompletedOnboarding {
            Task {
                await appState.scan()
                appState.runScheduledAutoCleanIfDue()
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.tick() }
        }
        registerLoginItemIfNeeded()
    }

    private func tick() {
        guard let appState, appState.hasCompletedOnboarding else { return }
        let dueForWeekly = (appState.lastScanDate.map { Date().timeIntervalSince($0) > weekInterval }) ?? true
        let lowSpace = isFreeSpaceBelow(percent: 10)
        if dueForWeekly || lowSpace {
            Task {
                await appState.scan()
                appState.runScheduledAutoCleanIfDue()
            }
        } else {
            // Even without a fresh scan, the auto-clean interval may have
            // elapsed against results we already have.
            appState.runScheduledAutoCleanIfDue()
        }
    }

    private func isFreeSpaceBelow(percent: Double) -> Bool {
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ), let free = values.volumeAvailableCapacityForImportantUsage,
           let total = values.volumeTotalCapacity, total > 0
        else { return false }
        return (Double(free) / Double(total)) * 100 < percent
    }

    private func registerLoginItemIfNeeded() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        try? service.register()
    }
}
