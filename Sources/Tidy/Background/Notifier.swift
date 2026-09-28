import Foundation
import UserNotifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyIfWorthwhile(result: ScanResult) {
        let reclaimable = result.safeAutoCleanBytes
        guard reclaimable > 500_000_000 else { return } // only bug the user above ~500MB
        let gb = Double(reclaimable) / 1_000_000_000
        send(
            title: "Tidy found space to reclaim",
            body: String(format: "%.1f GB of caches and stale build data can be cleared safely.", gb)
        )
    }

    static func notifyInstallerFound(name: String, appName: String) {
        send(title: "Installer no longer needed", body: "\(name) — \(appName) is already installed.")
    }

    static func notifyAutoClean(bytes: Int64) {
        let sizeString = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        send(title: "Tidy cleaned up automatically", body: "Freed \(sizeString) of caches and stale build data.")
    }

    private static func send(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
