import Foundation

actor FileSystemScanner {
    static let protectedPaths: Set<String> = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/Library/Extensions",
        "/private/var/db"
    ]

    func scan(root: URL, maxDepth: Int, minSize: Int64, includeHidden: Bool) async -> [URL] {
        let rootPath = root.standardizedFileURL.path
        // If root itself is protected, skip entirely.
        if isProtected(rootPath) { return [] }

        var results: [URL] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path

            // Skip protected paths and descendants.
            if isProtected(path) {
                enumerator.skipDescendants()
                continue
            }

            // Depth check relative to root.
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
            let depth = relative.isEmpty ? 0 : relative.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            // Hidden handling.
            let name = url.lastPathComponent
            if !includeHidden && name.hasPrefix(".") { continue }

            // Symlink handling: skip symlinks that resolve outside root.
            if let values = try? url.resourceValues(forKeys: Set(keys)),
               values.isSymbolicLink == true {
                if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
                    let resolved = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL.path
                    if !resolved.hasPrefix(rootPath) {
                        enumerator.skipDescendants()
                        continue
                    }
                } else {
                    continue
                }
            }

            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }

            let size = Int64(values.fileSize ?? 0)
            if size >= minSize {
                results.append(url)
            }
        }
        return results
    }

    private func isProtected(_ path: String) -> Bool {
        for p in FileSystemScanner.protectedPaths {
            if path == p || path.hasPrefix(p + "/") { return true }
        }
        return false
    }
}
