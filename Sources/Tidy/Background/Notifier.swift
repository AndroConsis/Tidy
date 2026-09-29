import Foundation
import UserNotifications

enum Notifier {
    /// `completion` fires on the main queue once the user actually answers
    /// the system permission dialog — which can take a while, since it's
    /// modal and waits on them. Callers that want to reflect the outcome in
    /// UI should use this instead of polling `getNotificationSettings` on a
    /// fixed timer, which just reads stale "not determined" state while the
    /// dialog is still up.
    static func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Tidy: notification authorization request failed: \(error.localizedDescription)")
            }
            DispatchQueue.main.async { completion?(granted) }
        }
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
        UNUserNotificationCenter.current().add(request) { error in
            // add() succeeds even when the user never granted permission —
            // the system just quietly won't show it — so this only ever
            // catches genuine delivery errors, but those were previously
            // impossible to diagnose since the completion handler was unused.
            if let error {
                print("Tidy: failed to deliver notification \"\(title)\": \(error.localizedDescription)")
            }
        }
    }
}
