import Foundation

/// User-configurable preferences persisted in Application Support.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Paths the user wants to protect from cleaning (whitelist).
    /// Directory entries protect everything underneath them.
    public var protectedPaths: [String]

    /// Minimum size in bytes for a file to be classified as "large".
    /// Aligned with the default used by `LargeFileFinder`.
    public var largeFileThresholdBytes: Int64

    public init(
        protectedPaths: [String] = [],
        largeFileThresholdBytes: Int64 = 100 * 1024 * 1024
    ) {
        self.protectedPaths = protectedPaths
        self.largeFileThresholdBytes = largeFileThresholdBytes
    }

    /// Default, empty settings.
    public static let `default` = AppSettings()
}

/// Persists `AppSettings` to `~/Library/Application Support/MacCleaner/settings.json`.
public final class SettingsStore {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let f = fileURL {
            self.fileURL = f
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("MacCleaner", isDirectory: true)
            self.fileURL = base.appendingPathComponent("settings.json")
        }
    }

    /// Loads settings, falling back to defaults when missing or unreadable.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Persists settings, creating the parent directory as needed.
    public func save(_ settings: AppSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Whitelist (protected paths)

    public func protectedPaths() -> [String] {
        load().protectedPaths
    }

    /// Adds a path to the whitelist, de-duplicating and keeping sorted order.
    public func addProtectedPath(_ path: String) throws {
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return }
        var settings = load()
        guard !settings.protectedPaths.contains(normalized) else { return }
        settings.protectedPaths.append(normalized)
        settings.protectedPaths.sort()
        try save(settings)
    }

    public func removeProtectedPath(_ path: String) throws {
        let normalized = normalize(path)
        var settings = load()
        settings.protectedPaths.removeAll { $0 == normalized }
        try save(settings)
    }

    // MARK: - Thresholds

    public func setLargeFileThreshold(bytes: Int64) throws {
        var settings = load()
        settings.largeFileThresholdBytes = bytes
        try save(settings)
    }

    private func normalize(_ path: String) -> String {
        (path as NSString).standardizingPath
    }
}
