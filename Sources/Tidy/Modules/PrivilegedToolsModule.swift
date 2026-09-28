import Foundation

/// Installed developer tools that live outside the user's home folder, so
/// removing them needs an admin password. Tidy still detects and lists
/// them — it just asks macOS's own authorization dialog to do the deleting,
/// or hands off to the vendor's own uninstaller when one exists.
enum PrivilegedToolsModule {
    static func scan() -> [CleanableItem] {
        var items: [CleanableItem] = []

        // PostgreSQL 16 (EDB/Postgres.app-style installer under /Library).
        // Owned by the system "postgres" account — not writable by an admin
        // user directly, and it may hold a live database, so Tidy always
        // routes through the vendor's own uninstaller when it's present
        // rather than an rm -rf of a data directory.
        let pgDir = "/Library/PostgreSQL/16"
        if FSUtil.exists(pgDir) {
            let uninstaller = "/Applications/PostgreSQL 16/Uninstall PostgreSQL.app"
            let size = FSUtil.size(of: URL(fileURLWithPath: pgDir))
            items.append(CleanableItem(
                name: "PostgreSQL 16",
                path: pgDir,
                paths: [pgDir],
                sizeBytes: size,
                lastModified: FSUtil.lastModified(of: URL(fileURLWithPath: pgDir)),
                safety: .review,
                category: .system,
                explanation: FSUtil.exists(uninstaller)
                    ? "Installed database server, owned by the system \"postgres\" account. This opens the vendor's own uninstaller (it may hold a live database, so Tidy won't touch it directly)."
                    : "Installed database server, owned by the system \"postgres\" account. Removing it needs your admin password — macOS will ask for it directly.",
                action: FSUtil.exists(uninstaller)
                    ? .launchApp(uninstaller)
                    : .privilegedShell("rm -rf '\(pgDir)'")
            ))
        }

        // python.org's 3.10 framework install. Not the system's default
        // python3, lives under /Library + /Applications, so it needs admin
        // rights to remove — but it's just files, safe to rm -rf directly.
        let pyFramework = "/Library/Frameworks/Python.framework/Versions/3.10"
        if FSUtil.exists(pyFramework) {
            let extraAppPath = "/Applications/Python 3.10"
            var allPaths = [pyFramework]
            if FSUtil.exists(extraAppPath) { allPaths.append(extraAppPath) }
            let totalSize = allPaths.reduce(Int64(0)) { $0 + FSUtil.size(of: URL(fileURLWithPath: $1)) }
            let shellCommand = allPaths.map { "rm -rf '\($0)'" }.joined(separator: " && ")

            items.append(CleanableItem(
                name: "Python 3.10 (python.org)",
                path: pyFramework,
                paths: allPaths,
                sizeBytes: totalSize,
                lastModified: FSUtil.lastModified(of: URL(fileURLWithPath: pyFramework)),
                safety: .review,
                category: .system,
                explanation: "Old python.org 3.10 install — not your default python3. Lives outside your home folder, so removing it needs your admin password; macOS will ask for it directly.",
                action: .privilegedShell(shellCommand)
            ))
        }

        return items
    }
}
