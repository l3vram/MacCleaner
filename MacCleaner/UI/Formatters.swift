import Foundation

/// Shared formatting helpers for the UI.
enum Format {
    /// Human-readable byte count (e.g. "1.2 GB") using the user's locale.
    static func bytes(_ count: Int64) -> String {
        guard count > 0 else { return "0 bytes" }
        return ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
