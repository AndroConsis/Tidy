import Foundation

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let name: String
    let paths: [String]
    let sizeBytes: Int64
    let category: String
}

/// Append-only record of every removal Tidy performs, so the user can see
/// exactly what was done and when. Stored at
/// ~/Library/Application Support/Tidy/actionlog.json
enum ActionLog {
    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("actionlog.json")
    }

    static func read() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([LogEntry].self, from: data)) ?? []
    }

    static func append(_ entry: LogEntry) {
        var entries = read()
        entries.insert(entry, at: 0)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: fileURL)
        }
    }
}
