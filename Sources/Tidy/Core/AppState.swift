import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var result = ScanResult()
    @Published var isScanning = false
    @Published var lastScanDate: Date?
    @Published var lastError: String?
    @Published var recentActions: [LogEntry] = ActionLog.read()

    // Auto-clean settings, persisted in UserDefaults. Only ever touches
    // .regenerable ("SAFE") items — REVIEW and MANUAL items always require
    // an explicit click, scheduled or not.
    @Published var autoCleanEnabled: Bool {
        didSet { UserDefaults.standard.set(autoCleanEnabled, forKey: "autoCleanEnabled") }
    }
    @Published var autoCleanFrequencyDays: Int {
        didSet { UserDefaults.standard.set(autoCleanFrequencyDays, forKey: "autoCleanFrequencyDays") }
    }
    @Published var lastAutoCleanDate: Date? {
        didSet { UserDefaults.standard.set(lastAutoCleanDate, forKey: "lastAutoCleanDate") }
    }

    /// Gates the first-run welcome flow. False until the user finishes it once.
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    init() {
        let defaults = UserDefaults.standard
        autoCleanEnabled = defaults.object(forKey: "autoCleanEnabled") as? Bool ?? false
        autoCleanFrequencyDays = defaults.object(forKey: "autoCleanFrequencyDays") as? Int ?? 7
        lastAutoCleanDate = defaults.object(forKey: "lastAutoCleanDate") as? Date
        hasCompletedOnboarding = defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false
    }

    var isAutoCleanDue: Bool {
        guard autoCleanEnabled else { return false }
        let interval = TimeInterval(autoCleanFrequencyDays * 24 * 60 * 60)
        return (lastAutoCleanDate.map { Date().timeIntervalSince($0) > interval }) ?? true
    }

    var freeBytes: Int64 {
        (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
    }

    func scan() async {
        isScanning = true
        result = await Scanner.runFullScan()
        lastScanDate = Date()
        isScanning = false
        Notifier.notifyIfWorthwhile(result: result)
    }

    func clean(_ item: CleanableItem) {
        do {
            _ = try Cleaner.clean(item)
            recentActions = ActionLog.read()
            // launchApp hands off to a vendor uninstaller wizard — nothing is
            // actually removed yet, so keep the row until the next rescan.
            if case .launchApp = item.action {} else {
                removeFromResult(item)
            }
        } catch CleanerError.cancelled {
            // User declined the admin prompt — not an error worth surfacing.
        } catch {
            lastError = "Couldn't clean \(item.name): \(error.localizedDescription)"
        }
    }

    @discardableResult
    func cleanAllRegenerable() -> Int64 {
        let targets = result.all.filter { $0.safety == .regenerable }
        var freed: Int64 = 0
        for item in targets {
            do {
                freed += try Cleaner.clean(item)
            } catch {
                lastError = "Couldn't clean \(item.name): \(error.localizedDescription)"
            }
        }
        recentActions = ActionLog.read()
        Task { await scan() }
        return freed
    }

    /// Called by the Scheduler on its periodic tick. Only fires if the user
    /// turned auto-clean on and the configured interval has elapsed.
    func runScheduledAutoCleanIfDue() {
        guard isAutoCleanDue, result.safeAutoCleanBytes > 0 else { return }
        let freed = cleanAllRegenerable()
        lastAutoCleanDate = Date()
        if freed > 0 {
            Notifier.notifyAutoClean(bytes: freed)
        }
    }

    private func removeFromResult(_ item: CleanableItem) {
        result.xcodeDeviceSupport.removeAll { $0.id == item.id }
        result.xcodeSimulators.removeAll { $0.id == item.id }
        result.xcodeBuildData.removeAll { $0.id == item.id }
        result.devCaches.removeAll { $0.id == item.id }
        result.appCaches.removeAll { $0.id == item.id }
        result.installers.removeAll { $0.id == item.id }
        result.unusedApps.removeAll { $0.id == item.id }
    }
}
