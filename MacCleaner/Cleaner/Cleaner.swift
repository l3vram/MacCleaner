import Foundation

public struct PlannedAction: Equatable {
    public let url: URL
    public let action: String
    public let bytes: Int64
    public init(url: URL, action: String, bytes: Int64) {
        self.url = url; self.action = action; self.bytes = bytes
    }
}

public enum CleanerError: Error, Equatable {
    case protectedPath(String)
    case outsideAllowedRoots(String)
    case symlinkEscape(String)
    case confirmationRequired
    case trashFailed(String)
}

public final class Cleaner {
    public static let protectedPaths: [String] = [
        "/System", "/Library", "/usr", "/bin", "/sbin", "/etc", "/var", "/private",
        "/Applications", "/Volumes"
    ]

    public static func allowedRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home, home.appendingPathComponent("Library/Caches")]
    }

    public static func validate(_ url: URL, whitelist: [String]? = nil) throws {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let path = resolved.path
        // hardcoded protected system paths
        for p in protectedPaths {
            if path == p || path.hasPrefix(p + "/") { throw CleanerError.protectedPath(path) }
        }
        // user whitelist (persisted protected paths); nil means load from SettingsStore
        let whitelisted = whitelist ?? SettingsStore().load().protectedPaths
        for p in whitelisted {
            let sp = (p as NSString).standardizingPath
            guard !sp.isEmpty else { continue }
            if path == sp || path.hasPrefix(sp + "/") { throw CleanerError.protectedPath(path) }
        }
        // ensure under allowed roots
        let roots = allowedRoots().map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        let ok = roots.contains { path == $0 || path.hasPrefix($0 + "/") }
        if !ok { throw CleanerError.outsideAllowedRoots(path) }
        // symlink escape: original vs resolved parent
        if url.path != resolved.path {
            // if symlink points outside allowed roots
            let origResolvedParent = url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            if !roots.contains(where: { origResolvedParent == $0 || origResolvedParent.hasPrefix($0 + "/") }) {
                throw CleanerError.symlinkEscape(path)
            }
        }
    }

    public static func fileSize(_ url: URL) -> Int64 {
        if let vals = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey]),
           vals.isDirectory == false, let s = vals.fileSize {
            return Int64(s)
        }
        var total: Int64 = 0
        if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in en {
                if let s = try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(s) }
            }
        }
        return total
    }

    public static func preview(urls: [URL]) -> [PlannedAction] {
        urls.map { u in PlannedAction(url: u, action: "trash", bytes: fileSize(u)) }
    }

    public static func trash(urls: [URL], whitelist: [String]? = nil, log: OperationLog? = nil) throws -> [URL] {
        var resulting: [URL] = []
        for u in urls {
            try validate(u, whitelist: whitelist)
            // Measure before moving: the source path no longer exists afterwards.
            let bytes = fileSize(u)
            var res: NSURL?
            try FileManager.default.trashItem(at: u, resultingItemURL: &res)
            if let r = res as URL? { resulting.append(r) }
            log?.append(action: "trash", source: u, destination: res as URL?, bytes: bytes)
        }
        return resulting
    }

    public static func trashDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    /// Total size of the items currently in the user's Trash.
    public static func trashSize(trash: URL = trashDirectory()) -> Int64 {
        let contents = (try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)) ?? []
        return contents.reduce(0) { $0 + fileSize($1) }
    }

    /// Permanently deletes everything in the user's Trash. This is irreversible,
    /// so it is a separate, explicitly confirmed action — never part of Clean.
    /// Returns the number of bytes freed.
    @discardableResult
    public static func emptyTrash(trash: URL = trashDirectory(), confirmationToken: String, log: OperationLog? = nil) throws -> Int64 {
        guard confirmationToken == "PERMANENT_DELETE_CONFIRMED" else { throw CleanerError.confirmationRequired }
        guard FileManager.default.fileExists(atPath: trash.path) else { return 0 }
        let contents = try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
        var freed: Int64 = 0
        for url in contents {
            let bytes = fileSize(url)
            try FileManager.default.removeItem(at: url)
            freed += bytes
            log?.append(action: "emptyTrash", source: url, destination: nil, bytes: bytes)
        }
        return freed
    }

    public static func deletePermanent(urls: [URL], whitelist: [String]? = nil, confirmationToken: String, log: OperationLog? = nil) throws {
        guard confirmationToken == "PERMANENT_DELETE_CONFIRMED" else { throw CleanerError.confirmationRequired }
        for u in urls {
            try validate(u, whitelist: whitelist)
            try FileManager.default.removeItem(at: u)
            log?.append(action: "deletePermanent", source: u, destination: nil, bytes: 0)
        }
    }
}
