import Foundation

struct LargeFile: Equatable {
    let url: URL
    let size: Int64
}

actor LargeFileFinder {
    private let scanner: FileSystemScanner

    init(scanner: FileSystemScanner = FileSystemScanner()) {
        self.scanner = scanner
    }

    func findLargest(
        root: URL,
        maxDepth: Int = 10,
        minSize: Int64 = 100 * 1024 * 1024,
        includeHidden: Bool = false,
        limit: Int = 50
    ) async -> [LargeFile] {
        let urls = await scanner.scan(root: root, maxDepth: maxDepth, minSize: minSize, includeHidden: includeHidden)
        var files: [LargeFile] = []
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
            files.append(LargeFile(url: url, size: size))
        }
        files.sort { $0.size > $1.size }
        if limit > 0 && files.count > limit {
            files = Array(files.prefix(limit))
        }
        return files
    }
}
