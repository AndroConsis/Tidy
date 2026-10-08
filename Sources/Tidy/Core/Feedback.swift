import AppKit
import StoreKit

/// Ratings and feedback, within App Review guideline 5.6.1: the in-app prompt
/// is only ever Apple's own review request (the system decides whether it
/// actually appears, at most a few times a year), never a custom "rate us"
/// dialog, and nothing is offered in exchange for a rating.
enum Feedback {
    static let appStoreID = "6817651013"
    static let email = "hello@prateekrathore.com"

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Asks once per app version, right after a clean the user started that
    /// freed at least 1 GB — the moment Tidy has just been useful. Scheduled
    /// auto-cleans never prompt, since the user didn't just act.
    @MainActor
    static func requestReviewIfEarned(freedBytes: Int64) {
        guard freedBytes >= 1_000_000_000 else { return }
        let defaults = UserDefaults.standard
        let version = appVersion
        guard defaults.string(forKey: "reviewRequestedForVersion") != version else { return }
        defaults.set(version, forKey: "reviewRequestedForVersion")
        // Give the "space freed" result a moment on screen first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if let controller = NSApp.keyWindow?.contentViewController {
                AppStore.requestReview(in: controller)
            } else {
                SKStoreReviewController.requestReview()
            }
        }
    }

    /// The "Rate Tidy" button: opens the App Store's write-a-review page.
    static func openWriteReview() {
        if let url = URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)?action=write-review") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens a pre-addressed email draft. Only the app and macOS versions are
    /// filled in, and nothing is sent until the user sends it themselves.
    static func sendFeedback() {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body = "\n\n—\nTidy \(appVersion) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [URLQueryItem(name: "subject", value: "Tidy feedback"), URLQueryItem(name: "body", value: body)]
        if let url = components.url { NSWorkspace.shared.open(url) }
    }
}
