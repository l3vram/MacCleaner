import Foundation

public enum Category: String, CaseIterable, Codable {
    case userCache
    case appCache
    case browserCache
    case devArtifact
    case largeFile
    case hiddenFile
    case log
    case trash
    case orphanedAppData

    public var displayName: String {
        switch self {
        case .userCache: return "User Caches"
        case .appCache: return "App Caches"
        case .browserCache: return "Browser Caches"
        case .devArtifact: return "Dev Artifacts"
        case .largeFile: return "Large Files"
        case .hiddenFile: return "Hidden Files"
        case .log: return "Logs"
        case .trash: return "Trash"
        case .orphanedAppData: return "Orphaned App Data"
        }
    }

    public var safeToDelete: Bool {
        switch self {
        case .userCache, .appCache, .browserCache, .devArtifact, .log, .trash:
            return true
        case .largeFile, .hiddenFile, .orphanedAppData:
            return false
        }
    }
}

public struct CategoryGroup {
    public let category: Category
    public var urls: [URL]
    public var totalSize: Int64
    public var safeToDelete: Bool { category.safeToDelete }
}

public struct Categorizer {
    public static let largeFileThreshold: Int64 = 100 * 1024 * 1024

    public static func classify(url: URL, size: Int64 = 0) -> Category {
        let path = url.standardizedFileURL.path
        let lower = path.lowercased()
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        if path.contains("/.Trash/") || path.contains("/Trash/") { return .trash }

        let browserKeywords = ["safari", "chrome", "firefox", "brave", "edge", "opera", "webkit"]
        if lower.contains("caches") && browserKeywords.contains(where: { lower.contains($0) }) {
            return .browserCache
        }

        let devNames: Set<String> = ["node_modules", "target", ".build", "dist", "build", "deriveddata", ".gradle"]
        let components = path.split(separator: "/").map { String($0).lowercased() }
        if components.contains(where: { devNames.contains($0) }) { return .devArtifact }
        if name.lowercased().hasPrefix("deriveddata") { return .devArtifact }

        if name.hasPrefix(".") { return .hiddenFile }

        if ext == "log" || lower.contains("/logs/") || lower.contains("logs/") { return .log }

        if lower.contains("/library/caches/") || lower.contains("/caches/") {
            return .userCache
        }

        if size >= largeFileThreshold { return .largeFile }

        if lower.contains("application support") || lower.contains("containers") {
            return .orphanedAppData
        }

        return .appCache
    }

    public static func categorize(urls: [URL]) -> [CategoryGroup] {
        var groups: [Category: [URL]] = [:]
        var sizes: [Category: Int64] = [:]
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            let cat = classify(url: url, size: size)
            groups[cat, default: []].append(url)
            sizes[cat, default: 0] += size
        }
        return Category.allCases.compactMap { cat in
            guard let urls = groups[cat], !urls.isEmpty else { return nil }
            return CategoryGroup(category: cat, urls: urls, totalSize: sizes[cat] ?? 0)
        }
    }
}
