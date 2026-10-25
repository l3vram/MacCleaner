import Foundation

public final class WhitelistStore {
    public let fileURL: URL
    public init(fileURL: URL? = nil) {
        if let f = fileURL { self.fileURL = f; return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("whitelist.json")
    }
    public func load() -> [String] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    public func save(_ paths: [String]) throws {
        let data = try JSONEncoder().encode(paths)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }
    public func add(_ path: String) throws {
        var cur = load(); if !cur.contains(path) { cur.append(path) }; try save(cur)
    }
    public func remove(_ path: String) throws {
        var cur = load(); cur.removeAll { $0 == path }; try save(cur)
    }
}
