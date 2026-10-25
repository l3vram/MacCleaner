import SwiftUI
import Combine

/// View model for the Optimize (system maintenance) feature.
@MainActor
final class OptimizeViewModel: ObservableObject {
    @Published var actions: [OptimizeAction] = []
    @Published var results: [OptimizeResult] = []
    @Published var isRunning = false
    @Published var message: String?

    init() {
        actions = Optimizer().actions()
    }

    func runAll() async {
        isRunning = true
        defer { isRunning = false }
        message = nil
        let result = await Task.detached(priority: .userInitiated) {
            Optimizer().runAll()
        }.value
        results = result
        message = "Completed \(result.filter { $0.success }.count) of \(result.count) tasks."
    }
}

/// Lists and runs system maintenance tasks (DNS flush, cache rebuilds, etc.).
struct OptimizeView: View {
    @StateObject private var viewModel = OptimizeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(viewModel.actions.indices, id: \.self) { index in
                    let action = viewModel.actions[index]
                    let result = index < viewModel.results.count ? viewModel.results[index] : nil
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(action.step.rawValue)
                                .font(.headline)
                            Text(action.commandString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if action.requiresSudo {
                                Label("Requires admin rights", systemImage: "lock")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let result {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset)
        }
        .navigationTitle("Optimize")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("System maintenance tasks")
                .font(.headline)
            Spacer()
            if viewModel.isRunning {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await viewModel.runAll() }
            } label: {
                Label(viewModel.isRunning ? "Running…" : "Run All", systemImage: "bolt")
            }
            .disabled(viewModel.isRunning)
        }
        .padding()
    }
}
