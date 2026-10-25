import Foundation

public final class HiddenFileDetector {
    public init() {}

    public func detect(root: URL, maxDepth: Int = 10) -> [URL: [URL]] {
        let rootPath = root.standardizedFileURL.path
        var grouped: [URL: [URL]] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return [:] }

        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : path
            let depth = relative.isEmpty ? 0 : relative.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = url.lastPathComponent
            guard name.hasPrefix("."), name != ".", name != ".." else { continue }

            let parent = url.deletingLastPathComponent()
            grouped[parent, default: []].append(url)
        }
        return grouped
    }
}
