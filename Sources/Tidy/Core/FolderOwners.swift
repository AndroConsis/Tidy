import AppKit

/// Works out which app or tool a folder belongs to, whether that app is
/// still installed, and so whether the folder is safe to remove. Used by the
/// Disk Map inspector and to find an app's leftovers when uninstalling it.
enum FolderOwners {
    struct Owner {
        let name: String
        /// Apps that use this folder. Empty for command-line tools.
        let bundleIDs: [String]
        /// What's inside, in plain words.
        let contents: String
        /// Never suggest removing it (keys, credentials, iCloud…).
        var keep = false
    }

    enum Status: Equatable {
        case keep
        case appInstalled(String)
        case appNotInstalled
        case tool
        case personal
        case system
    }

    struct Verdict {
        let owner: String
        let contents: String
        let status: Status

        var canRemove: Bool { status == .appNotInstalled || status == .tool }

        var advice: String {
            switch status {
            case .keep: return "Keep it. Tidy never removes this."
            case .appInstalled(let app): return "\(app) is installed and uses it. Removing it deletes \(contents)."
            case .appNotInstalled: return "\(owner) isn't installed, so this is leftover data. Safe to remove unless you plan to reinstall it."
            case .tool: return "Made by a command-line tool. Remove it only if you no longer use \(owner)."
            case .personal: return "Your own files. Look inside before removing anything."
            case .system: return "Managed by macOS. Tidy cleans the safe parts of it for you."
            }
        }
    }

    /// Folders keyed by their path inside the Home folder.
    static let known: [String: Owner] = [
        ".lmstudio": Owner(name: "LM Studio", bundleIDs: ["ai.elementlabs.lmstudio", "ai.elementlabs.bionic"],
                           contents: "downloaded AI models, extensions and saved sign-ins"),
        ".cache/lm-studio": Owner(name: "LM Studio", bundleIDs: ["ai.elementlabs.lmstudio", "ai.elementlabs.bionic"],
                                  contents: "downloaded AI models"),
        ".ollama": Owner(name: "Ollama", bundleIDs: ["com.electron.ollama"], contents: "downloaded AI models"),
        ".cache/huggingface": Owner(name: "Hugging Face tools", bundleIDs: [], contents: "downloaded AI models, which download again when needed"),
        ".android": Owner(name: "Android Studio", bundleIDs: ["com.google.android.studio"], contents: "emulators and Android settings"),
        "Library/Android": Owner(name: "Android Studio", bundleIDs: ["com.google.android.studio"], contents: "the Android SDK and system images"),
        ".docker": Owner(name: "Docker", bundleIDs: ["com.docker.docker"], contents: "Docker settings and sign-ins"),
        ".vscode": Owner(name: "Visual Studio Code", bundleIDs: ["com.microsoft.VSCode"], contents: "editor extensions"),
        ".cursor": Owner(name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"], contents: "editor extensions"),
        ".gradle": Owner(name: "Gradle", bundleIDs: [], contents: "build caches (cleaned safely under Developer)"),
        ".m2": Owner(name: "Maven", bundleIDs: [], contents: "downloaded Java libraries"),
        ".npm": Owner(name: "npm", bundleIDs: [], contents: "downloaded packages"),
        ".yarn": Owner(name: "Yarn", bundleIDs: [], contents: "downloaded packages"),
        ".bun": Owner(name: "Bun", bundleIDs: [], contents: "the Bun runtime and packages"),
        ".deno": Owner(name: "Deno", bundleIDs: [], contents: "the Deno runtime and packages"),
        ".nvm": Owner(name: "nvm", bundleIDs: [], contents: "installed Node.js versions"),
        ".pyenv": Owner(name: "pyenv", bundleIDs: [], contents: "installed Python versions"),
        ".conda": Owner(name: "Conda", bundleIDs: [], contents: "Python environments"),
        "anaconda3": Owner(name: "Anaconda", bundleIDs: [], contents: "Python and its packages"),
        "miniconda3": Owner(name: "Miniconda", bundleIDs: [], contents: "Python and its packages"),
        ".cargo": Owner(name: "Rust (Cargo)", bundleIDs: [], contents: "Rust tools and downloaded crates"),
        ".rustup": Owner(name: "Rust (rustup)", bundleIDs: [], contents: "installed Rust toolchains"),
        ".cocoapods": Owner(name: "CocoaPods", bundleIDs: [], contents: "the CocoaPods spec repository"),
        ".swiftpm": Owner(name: "Swift Package Manager", bundleIDs: [], contents: "package settings and caches"),
        ".expo": Owner(name: "Expo", bundleIDs: [], contents: "Expo tools and caches"),
        ".colima": Owner(name: "Colima", bundleIDs: [], contents: "container virtual machines"),
        ".minikube": Owner(name: "minikube", bundleIDs: [], contents: "Kubernetes virtual machines"),
        ".claude": Owner(name: "Claude Code", bundleIDs: [], contents: "settings and conversation history"),
        ".ssh": Owner(name: "SSH", bundleIDs: [], contents: "your SSH keys", keep: true),
        ".gnupg": Owner(name: "GnuPG", bundleIDs: [], contents: "your encryption keys", keep: true),
        ".kube": Owner(name: "Kubernetes", bundleIDs: [], contents: "cluster sign-ins", keep: true),
        ".config": Owner(name: "Command-line tools", bundleIDs: [], contents: "settings for many tools", keep: true),
        "Library/Mobile Documents": Owner(name: "iCloud Drive", bundleIDs: [], contents: "your iCloud Drive files", keep: true),
        "Library/Mail": Owner(name: "Mail", bundleIDs: [], contents: "your email", keep: true),
        "Library/Messages": Owner(name: "Messages", bundleIDs: [], contents: "your messages", keep: true),
        "Library/Developer": Owner(name: "Xcode", bundleIDs: ["com.apple.dt.Xcode"], contents: "build data, simulators and device support"),
    ]

    static let personalFolders: Set<String> = ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Projects"]

    /// Library folders whose subfolders are named after the app that made them.
    static let perAppLibraryFolders = ["Application Support", "Caches", "Logs", "HTTPStorages", "WebKit",
                                       "Saved Application State", "Containers", "Group Containers"]

    static func verdict(for url: URL, home: URL = FSUtil.home) -> Verdict? {
        let homePath = home.path + "/"
        guard url.path.hasPrefix(homePath) else { return nil }
        let relative = String(url.path.dropFirst(homePath.count))

        if let owner = known[relative] { return verdict(owner) }
        if personalFolders.contains(relative) || relative.hasSuffix(".photoslibrary") {
            return Verdict(owner: "You", contents: "your files", status: relative.hasSuffix(".photoslibrary") ? .keep : .personal)
        }
        if relative == "Library" {
            return Verdict(owner: "macOS and your apps", contents: "app data, caches and settings", status: .system)
        }

        // ~/Library/<per-app folder>/<app>
        let parts = relative.split(separator: "/").map(String.init)
        if parts.count == 3, parts[0] == "Library", perAppLibraryFolders.contains(parts[1]) {
            let name = parts[2].replacingOccurrences(of: ".savedState", with: "")
            if name.hasPrefix("com.apple.") || name.hasPrefix("group.com.apple.") {
                return Verdict(owner: "macOS", contents: "data for one of Apple's apps", status: .system)
            }
            if let app = installedApp(bundleID: name) ?? installedApp(named: name) {
                return Verdict(owner: app, contents: "\(app)'s data", status: .appInstalled(app))
            }
            if looksLikeBundleID(name) {
                return Verdict(owner: name, contents: "data from an app that's no longer installed", status: .appNotInstalled)
            }
        }
        return nil
    }

    private static func verdict(_ owner: Owner) -> Verdict {
        if owner.keep { return Verdict(owner: owner.name, contents: owner.contents, status: .keep) }
        if owner.bundleIDs.isEmpty { return Verdict(owner: owner.name, contents: owner.contents, status: .tool) }
        if let app = owner.bundleIDs.lazy.compactMap(installedApp(bundleID:)).first {
            return Verdict(owner: owner.name, contents: owner.contents, status: .appInstalled(app))
        }
        return Verdict(owner: owner.name, contents: owner.contents, status: .appNotInstalled)
    }

    /// Home-folder data that belongs to this app and no other installed app,
    /// for the uninstaller's leftover list.
    static func knownFolders(for bundleID: String, home: URL = FSUtil.home) -> [(url: URL, contents: String)] {
        known.compactMap { relative, owner in
            guard !owner.keep, owner.bundleIDs.contains(bundleID) else { return nil }
            // Shared with another app that's still installed (e.g. LM Studio and Bionic).
            let others = owner.bundleIDs.filter { $0 != bundleID }
            guard others.allSatisfy({ installedApp(bundleID: $0) == nil }) else { return nil }
            let url = home.appendingPathComponent(relative)
            return FSUtil.exists(url.path) ? (url, owner.contents) : nil
        }
    }

    static func installedApp(bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func installedApp(named name: String) -> String? {
        guard name.count >= 4 else { return nil }
        for base in ["/Applications", FSUtil.home.appendingPathComponent("Applications").path]
        where FSUtil.exists("\(base)/\(name).app") {
            return name
        }
        return nil
    }

    private static func looksLikeBundleID(_ name: String) -> Bool {
        let parts = name.split(separator: ".")
        return parts.count >= 3 && !name.contains(" ")
    }
}
