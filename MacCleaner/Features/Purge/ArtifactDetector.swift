import Foundation

/// A detected disposable dev-artifact directory (node_modules, build, etc.).
public struct Artifact: Equatable, Sendable {
    public let url: URL
    /// Matched directory name, e.g. "node_modules".
    public let kind: String
    /// Total bytes under the directory (0 when unreadable).
    public let size: Int64
    /// Content modification date of the directory, if known.
    public let modified: Date?

    public init(url: URL, kind: String, size: Int64, modified: Date?) {
        self.url = url
        self.kind = kind
        self.size = size
        self.modified = modified
    }
}

/// Scans common project roots for dev-artifact directories and applies
/// safety exclusions (nested repos, deployment keypairs) and recency gating.
public final class ArtifactDetector {
    /// Directory names recognized as disposable build/dev artifacts.
    public static let artifactNames: Set<String> = [
        "node_modules", "target", ".build", "dist", "build",
        "DerivedData", ".gradle", ".m2"
    ]

    /// Keypair-like filenames that make a directory unsafe to purge.
    public static let keypairNames: Set<String> = [
        "id_rsa", "id_rsa.pub", "id_ed25519", "id_ed25519.pub",
        "id_ecdsa", "id_ecdsa.pub", "id_dsa", "id_dsa.pub"
    ]

    /// Keypair-like file extensions that make a directory unsafe to purge.
    public static let keypairExtensions: Set<String> = ["pem", "p12", "key", "ppk"]

    /// Common roots where dev artifacts live.
    public static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("GitHub"),
            home.appendingPathComponent("dev"),
            home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
        ]
    }

    public init() {}

    /// Scans `roots` for artifact directories and returns them sorted by size (descending).
    ///
    /// - Parameters:
    ///   - roots: directories to scan.
    ///   - maxDepth: maximum directory depth relative to each root.
    ///   - recencyWindow: seconds; artifacts modified more recently than this are
    ///     excluded unless `includeRecent` is true.
    ///   - includeRecent: when false (default) recently-modified artifacts are excluded,
    ///     matching the "default unselected" purge behavior.
    ///   - now: reference instant for recency checks (injectable for tests).
    public func detect(
        roots: [URL] = ArtifactDetector.defaultRoots(),
        maxDepth: Int = 5,
        recencyWindow: TimeInterval = 7 * 24 * 60 * 60,
        includeRecent: Bool = false,
        now: Date = Date()
    ) -> [Artifact] {
        var results: [Artifact] = []
        for root in roots {
            results.append(contentsOf: detectOne(root: root, maxDepth: maxDepth,
                                                recencyWindow: recencyWindow,
                                                includeRecent: includeRecent, now: now))
        }
        return results.sorted { $0.size > $1.size }
    }

    private func detectOne(
        root: URL,
        maxDepth: Int,
        recencyWindow: TimeInterval,
        includeRecent: Bool,
        now: Date
    ) -> [Artifact] {
        let rootPath = root.standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: rootPath) else { return [] }

        var results: [Artifact] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path

            // Depth relative to root.
            let relative = path.hasPrefix(rootPath + "/")
                ? String(path.dropFirst(rootPath.count + 1))
                : path
            let depth = relative.isEmpty ? 0 : relative.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true else { continue }

            let name = url.lastPathComponent
            guard ArtifactDetector.artifactNames.contains(name) else { continue }

            // Safety: skip artifacts containing a nested repo or deployment keypairs.
            guard isSafe(url) else {
                enumerator.skipDescendants()
                continue
            }

            // Recency: skip recently-modified artifacts by default.
            let modified = values.contentModificationDate
            if !includeRecent, let modified, now.timeIntervalSince(modified) < recencyWindow {
                enumerator.skipDescendants()
                continue
            }

            results.append(Artifact(url: url, kind: name, size: Cleaner.fileSize(url), modified: modified))
            // Do not descend into an artifact (avoids double-counting nested matches).
            enumerator.skipDescendants()
        }
        return results
    }

    /// A directory is safe to purge when it does not contain a nested `.git`
    /// repo or deployment keypairs (checked among its immediate children).
    private func isSafe(_ url: URL) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else {
            // Cannot inspect -> treat as unsafe (safety-first).
            return false
        }
        for child in children {
            let name = child.lastPathComponent
            if name == ".git" { return false }
            if ArtifactDetector.keypairNames.contains(name) { return false }
            let ext = child.pathExtension.lowercased()
            if !ext.isEmpty && ArtifactDetector.keypairExtensions.contains(ext) { return false }
        }
        return true
    }
}
