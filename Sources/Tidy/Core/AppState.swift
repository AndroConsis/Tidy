import Foundation
import SwiftUI
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    @Published var result = ScanResult()
    @Published var isScanning = false
    @Published var lastScanDate: Date?
    @Published var lastError: String?
    @Published var recentActions: [LogEntry] = ActionLog.read()
    let largeFiles = LargeFilesModel()
    let diskMap = DiskMapModel()
    let uninstaller = UninstallerModel()

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

    /// Opt-in only: App Review guideline 2.4.5(iii) forbids launching at
    /// login without the user's consent.
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            let service = SMAppService.mainApp
            guard launchAtLogin != (service.status == .enabled) else { return }
            do {
                if launchAtLogin { try service.register() } else { try service.unregister() }
            } catch {
                lastError = "Couldn't change the login item: \(error.localizedDescription)"
                launchAtLogin = service.status == .enabled
            }
        }
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

    #if DEBUG
    /// Demo recordings show a nearly full Mac regardless of this machine's disk.
    @Published var debugFreeBytes: Int64?
    #endif

    var freeBytes: Int64 {
        #if DEBUG
        if let debugFreeBytes { return debugFreeBytes }
        #endif
        return (try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
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
            let freed = try Cleaner.clean(item)
            recentActions = ActionLog.read()
            Feedback.requestReviewIfEarned(freedBytes: freed)
            // launchApp and reveal hand off to another app or to Finder —
            // nothing is removed yet, so keep the row until the next rescan.
            switch item.action {
            case .trash, .command: removeFromResult(item)
            case .launchApp, .reveal, .guide: break
            }
        } catch {
            lastError = "Couldn't clean \(item.name): \(error.localizedDescription)"
        }
    }

    @discardableResult
    func cleanAllRegenerable(userInitiated: Bool = true) -> Int64 {
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
        if userInitiated { Feedback.requestReviewIfEarned(freedBytes: freed) }
        Task { await scan() }
        return freed
    }

    /// Called by the Scheduler on its periodic tick. Only fires if the user
    /// turned auto-clean on and the configured interval has elapsed.
    func runScheduledAutoCleanIfDue() {
        guard isAutoCleanDue, result.safeAutoCleanBytes > 0 else { return }
        let freed = cleanAllRegenerable(userInitiated: false)
        lastAutoCleanDate = Date()
        if freed > 0 {
            Notifier.notifyAutoClean(bytes: freed)
        }
    }

    private func removeFromResult(_ item: CleanableItem) {
        result.xcodeDeviceSupport.removeAll { $0.id == item.id }
        result.xcodeSimulators.removeAll { $0.id == item.id }
        result.xcodeBuildData.removeAll { $0.id == item.id }
        result.android.removeAll { $0.id == item.id }
        result.devCaches.removeAll { $0.id == item.id }
        result.appCaches.removeAll { $0.id == item.id }
        result.installers.removeAll { $0.id == item.id }
        result.unusedApps.removeAll { $0.id == item.id }
        result.system.removeAll { $0.id == item.id }
    }
}
