import Foundation

/// Package-manager and build-tool caches. All of these are re-downloaded /
/// rebuilt automatically, so anything found here is `.regenerable`.
enum DevCachesModule {
    static let home = FSUtil.home

    struct KnownCache {
        let name: String
        let path: String
        let tool: String
    }

    static var knownCaches: [KnownCache] {
        [
            KnownCache(name: "Homebrew download cache", path: home.appendingPathComponent("Library/Caches/Homebrew").path, tool: "Homebrew"),
            KnownCache(name: "npm cache", path: home.appendingPathComponent(".npm").path, tool: "npm"),
            KnownCache(name: "pip cache", path: home.appendingPathComponent("Library/Caches/pip").path, tool: "pip"),
            KnownCache(name: "Yarn cache", path: home.appendingPathComponent("Library/Caches/Yarn").path, tool: "Yarn"),
            KnownCache(name: "CocoaPods cache", path: home.appendingPathComponent("Library/Caches/CocoaPods").path, tool: "CocoaPods"),
            KnownCache(name: "Gradle cache", path: home.appendingPathComponent(".gradle/caches").path, tool: "Gradle"),
            KnownCache(name: "Maven repository cache", path: home.appendingPathComponent(".m2/repository").path, tool: "Maven"),
            KnownCache(name: "SwiftPM cache", path: home.appendingPathComponent("Library/Caches/org.swift.swiftpm").path, tool: "SwiftPM"),
            KnownCache(name: "Playwright browser cache", path: home.appendingPathComponent("Library/Caches/ms-playwright").path, tool: "Playwright"),
            KnownCache(name: "Playwright (Go) cache", path: home.appendingPathComponent("Library/Caches/ms-playwright-go").path, tool: "Playwright"),
            KnownCache(name: "node-gyp cache", path: home.appendingPathComponent("Library/Caches/node-gyp").path, tool: "node-gyp"),
            KnownCache(name: "pnpm store", path: home.appendingPathComponent("Library/pnpm/store").path, tool: "pnpm"),
        ]
    }

    static func scan() -> [CleanableItem] {
        knownCaches.compactMap { cache in
            guard FSUtil.exists(cache.path) else { return nil }
            let size = FSUtil.size(of: URL(fileURLWithPath: cache.path))
            guard size > 5_000_000 else { return nil }
            return CleanableItem(
                name: cache.name,
                path: cache.path,
                paths: [cache.path],
                sizeBytes: size,
                lastModified: FSUtil.lastModified(of: URL(fileURLWithPath: cache.path)),
                safety: .regenerable,
                category: .devCache,
                explanation: "\(cache.tool) re-downloads whatever it needs the next time you use it.",
                action: .trash
            )
        }
    }

    /// node_modules / .venv / build "target" folders inside project directories
    /// that haven't been touched in a long time. Review-only: these can be
    /// large, but re-running install/build reproduces them exactly.
    static func scanStaleProjectArtifacts(under roots: [String], staleDays: Int = 90) -> [CleanableItem] {
        var items: [CleanableItem] = []
        let artifactNames: Set<String> = ["node_modules", ".venv", "venv", "target", "build", ".build"]

        for root in roots {
            guard FSUtil.exists(root) else { continue }
            let projects = FSUtil.subdirectories(of: root)
            for project in projects {
                let projectMTime = FSUtil.lastModified(of: project)
                guard FSUtil.daysSince(projectMTime) >= staleDays else { continue }
                for artifact in artifactNames {
                    let artifactPath = project.appendingPathComponent(artifact)
                    guard FSUtil.exists(artifactPath.path) else { continue }
                    let size = FSUtil.size(of: artifactPath)
                    guard size > 20_000_000 else { continue }
                    items.append(CleanableItem(
                        name: "\(project.lastPathComponent)/\(artifact)",
                        path: artifactPath.path,
                        paths: [artifactPath.path],
                        sizeBytes: size,
                        lastModified: projectMTime,
                        safety: .review,
                        category: .devCache,
                        explanation: "Dependency/build folder in a project untouched for \(FSUtil.daysSince(projectMTime)) days. Reinstall with your package manager if you come back to it.",
                        action: .trash
                    ))
                }
            }
        }
        return items
    }
}
