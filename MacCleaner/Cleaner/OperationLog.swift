import Foundation

public final class OperationLog {
    public let fileURL: URL
    public init(fileURL: URL? = nil) {
        if let f = fileURL { self.fileURL = f; return }
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MacCleaner", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("operations.log")
    }
    public func append(action: String, source: URL, destination: URL?, bytes: Int64) {
        let ts = ISO8601DateFormatter().string(from: Date())
        var line = "\(ts) action=\(action) source=\(source.path) bytes=\(bytes)"
        if let d = destination { line += " dest=\(d.path)" }
        line += "\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let fh = try? FileHandle(forWritingTo: fileURL) {
                    fh.seekToEndOfFile(); fh.write(data); try? fh.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
