import Foundation
import AppKit

enum CleanerError: Error, LocalizedError {
    case commandFailed(String)
    case cancelled
    var errorDescription: String? {
        switch self {
        case .commandFailed(let msg): return msg
        case .cancelled: return "Cancelled"
        }
    }
}

/// Executes the action attached to a CleanableItem. Every code path here
/// is reversible (Trash) or targets a tool's own cache-clearing command —
/// Tidy never calls rm -rf and never touches a path outside what a
/// Module explicitly listed.
enum Cleaner {
    @discardableResult
    static func clean(_ item: CleanableItem) throws -> Int64 {
        switch item.action {
        case .trash:
            for p in item.paths where FSUtil.exists(p) {
                try FSUtil.trash(p)
            }
        case .command(let args):
            guard let tool = args.first else { return 0 }
            let (status, output) = FSUtil.run(resolvedPath(for: tool), Array(args.dropFirst()))
            if status != 0 {
                throw CleanerError.commandFailed(output)
            }
        case .privilegedShell(let command):
            try runPrivileged(command)
        case .guide:
            // Nothing to do programmatically; UI shows instructions instead.
            return 0
        case .launchApp(let path):
            // Hands off to the vendor's own uninstaller. We can't know how much
            // space it frees, or whether the user finishes it, so no log entry
            // (nothing has actually been removed by Tidy itself).
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            return 0
        }

        ActionLog.append(LogEntry(
            date: Date(),
            name: item.name,
            paths: item.paths,
            sizeBytes: item.sizeBytes,
            category: item.category.rawValue
        ))
        return item.sizeBytes
    }

    private static func resolvedPath(for tool: String) -> String {
        if tool.hasPrefix("/") { return tool }
        let candidates = ["/usr/bin/\(tool)", "/usr/local/bin/\(tool)", "/opt/homebrew/bin/\(tool)"]
        return candidates.first(where: { FSUtil.exists($0) }) ?? "/usr/bin/\(tool)"
    }

    /// Runs a shell command with administrator privileges via macOS's own
    /// authorization dialog. The user enters their own password/Touch ID
    /// into a system-owned prompt — Tidy's code never sees or stores it.
    private static func runPrivileged(_ command: String) throws {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw CleanerError.commandFailed("Could not build the admin request.")
        }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let number = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
            if number == -128 { throw CleanerError.cancelled } // user clicked Cancel
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            throw CleanerError.commandFailed(message)
        }
    }
}
