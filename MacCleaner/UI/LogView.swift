import SwiftUI
import Combine

/// View model for the operation log viewer.
@MainActor
final class LogViewModel: ObservableObject {
    @Published var lines: [String] = []
    @Published var message: String?

    private let log = OperationLog()

    var logPath: String { log.fileURL.path }

    func reload() {
        if let data = try? Data(contentsOf: log.fileURL),
           let text = String(data: data, encoding: .utf8) {
            lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        } else {
            lines = []
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: log.fileURL)
        lines = []
        message = "Log cleared."
    }
}

/// Shows the persisted operation log (every trash/permanent deletion).
struct LogView: View {
    @StateObject private var viewModel = LogViewModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(viewModel.logPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Reload") { viewModel.reload() }
                Button("Clear", role: .destructive) { viewModel.clear() }
            }
            .padding()

            if viewModel.lines.isEmpty {
                Text("No operations logged yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(viewModel.lines.reversed()), id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Log")
        .onAppear { viewModel.reload() }
    }
}
