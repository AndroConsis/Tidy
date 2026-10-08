import AppKit

/// Tidy is sandboxed, so it can only read the user's real home folder
/// (~/Library/Developer, ~/Library/Caches, ~/.npm, …) after the user picks it
/// once in an Open panel. The grant is kept as a security-scoped bookmark and
/// re-opened on every launch.
@MainActor
final class FolderAccess: ObservableObject {
    static let shared = FolderAccess()

    @Published private(set) var hasHomeAccess = false
    /// Needed only to move apps to the Trash from the Uninstaller; Tidy can
    /// list apps without it.
    @Published private(set) var hasApplicationsAccess = false

    private let bookmarkKey = "homeFolderBookmark"
    private let applicationsBookmarkKey = "applicationsFolderBookmark"
    private var accessedURL: URL?
    private var applicationsURL: URL?
    static let applicationsFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)

    private init() {
        restore()
        restoreApplications()
    }

    /// Shows the Open panel pointed at /Applications so the Uninstaller can
    /// move apps the user chooses to the Trash.
    @discardableResult
    func requestApplicationsAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "To move apps you choose to the Trash, Tidy needs access to your Applications folder. Click Grant Access without changing the selection."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = Self.applicationsFolder
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              url.standardizedFileURL.path == Self.applicationsFolder.path else { return false }
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return false }
        UserDefaults.standard.set(data, forKey: applicationsBookmarkKey)
        applicationsURL?.stopAccessingSecurityScopedResource()
        hasApplicationsAccess = url.startAccessingSecurityScopedResource()
        applicationsURL = hasApplicationsAccess ? url : nil
        return hasApplicationsAccess
    }

    private func restoreApplications() {
        guard let data = UserDefaults.standard.data(forKey: applicationsBookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            UserDefaults.standard.removeObject(forKey: applicationsBookmarkKey)
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: applicationsBookmarkKey)
        }
        hasApplicationsAccess = url.startAccessingSecurityScopedResource()
        applicationsURL = hasApplicationsAccess ? url : nil
    }

    /// Shows the Open panel pointed at the user's home folder. Returns true
    /// if the user granted it.
    @discardableResult
    func requestHomeAccess() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Tidy needs access to your Home folder to find caches and build data. Click Grant Access without changing the selection."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = FSUtil.home
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        guard url.standardizedFileURL.path == FSUtil.home.standardizedFileURL.path else {
            let alert = NSAlert()
            alert.messageText = "Please choose your Home folder"
            alert.informativeText = "Tidy scans fixed places inside \(FSUtil.home.path). Choose that folder itself (it was preselected) so every scan can reach them."
            alert.runModal()
            return false
        }

        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: bookmarkKey)
        } catch {
            return false
        }
        startAccessing(url)
        return true
    }

    #if DEBUG
    /// Screenshot mode renders sample data, so the grant banner shouldn't show.
    func pretendGrantedForScreenshots() { hasHomeAccess = true }
    #endif

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            return
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        startAccessing(url)
    }

    private func startAccessing(_ url: URL) {
        accessedURL?.stopAccessingSecurityScopedResource()
        hasHomeAccess = url.startAccessingSecurityScopedResource()
        accessedURL = hasHomeAccess ? url : nil
    }
}
