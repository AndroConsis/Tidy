import Foundation

/// How confident Tidy is that removing this item is safe.
enum Safety: String, Codable {
    case regenerable   // Tool/OS will recreate this automatically. Safe to auto-clean.
    case review        // Probably safe, but Tidy asks before touching it.
    case personal      // Tidy never deletes this itself; it only explains what to do.
}

enum ItemCategory: String, Codable, CaseIterable {
    case xcodeDeviceSupport = "Xcode Device Support"
    case xcodeSimulatorRuntime = "Simulator Runtime"
    case xcodeSimulatorDevice = "Simulator Device"
    case xcodeSimulatorCache = "Simulator Cache"
    case xcodeDerivedData = "Xcode Build Data"
    case xcodePreviews = "SwiftUI Previews"
    case xcodeDocumentation = "Xcode Documentation"
    case xcodeArchive = "Xcode Archive"
    case androidEmulator = "Android Emulator"
    case androidSystemImage = "Android System Image"
    case androidCache = "Android Cache"
    case devCache = "Developer Cache"
    case appCache = "App Cache"
    case orphanedSupport = "Orphaned App Data"
    case installer = "Downloaded Installer"
    case unusedApp = "Unused Application"
    case largeFile = "Large File"
    case uninstalledApp = "Uninstalled App"
    case system = "System"
}

/// What happens when the user asks Tidy to act on an item.
enum ItemAction {
    case trash                      // Move path(s) to ~/.Trash
    case command([String])          // Run a tool by absolute path (e.g. simctl)
    case guide(String)              // Not automatable; open a URL / show instructions
    case reveal(String)             // Owned by macOS or outside Tidy's sandbox; show it
                                     // in Finder so the user can remove it themselves.
    case launchApp(String)          // Hand off to another app's own uninstaller/GUI.
}

struct CleanableItem: Identifiable {
    let id = UUID()
    let name: String
    let path: String              // primary path, for display
    let paths: [String]           // all filesystem paths this item represents
    let sizeBytes: Int64
    let lastModified: Date?
    let safety: Safety
    let category: ItemCategory
    let explanation: String
    let action: ItemAction

    var sizeString: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct ScanResult {
    var xcodeDeviceSupport: [CleanableItem] = []
    var xcodeSimulators: [CleanableItem] = []
    var xcodeBuildData: [CleanableItem] = []
    var android: [CleanableItem] = []
    var devCaches: [CleanableItem] = []
    var appCaches: [CleanableItem] = []
    var installers: [CleanableItem] = []
    var system: [CleanableItem] = []

    var all: [CleanableItem] {
        xcodeDeviceSupport + xcodeSimulators + xcodeBuildData + android + devCaches + appCaches + installers + system
    }

    var reclaimableBytes: Int64 {
        all.filter { $0.safety != .personal }.reduce(0) { $0 + $1.sizeBytes }
    }

    var safeAutoCleanBytes: Int64 {
        all.filter { $0.safety == .regenerable }.reduce(0) { $0 + $1.sizeBytes }
    }
}
