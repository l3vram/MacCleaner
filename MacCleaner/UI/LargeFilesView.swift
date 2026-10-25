import SwiftUI
import Combine

/// View model for the Large Files feature.
@MainActor
final class LargeFilesViewModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var selected: Set<URL> = []
    @Published var isScanning = false
    @Published var isTrashing = false
    @Published var message: String?
    @Published var errorMessage: String?

    private let log = OperationLog()

    var selectedBytes: Int64 {
        files.filter { selected.contains($0.url) }.reduce(0) { $0 + $1.size }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        message = nil
        errorMessage = nil
        let threshold = SettingsStore().load().largeFileThresholdBytes
        let finder = LargeFileFinder()
        let home = FileManager.default.homeDirectoryForCurrentUser
        files = await finder.findLargest(root: home, minSize: threshold, limit: 100)
        selected.removeAll()
    }

    func trashSelected() {
        let urls = files.filter { selected.contains($0.url) }.map { $0.url }
        guard !urls.isEmpty else { return }
        isTrashing = true
        defer { isTrashing = false }
        message = nil
        errorMessage = nil
        do {
            let moved = try Cleaner.trash(urls: urls, log: log)
            message = "Moved \(moved.count) of \(urls.count) large files to Trash."
            let removed = Set(urls)
            files.removeAll { removed.contains($0.url) }
            selected.removeAll()
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// Lists the largest files in the home folder with trash-by-default cleanup.
struct LargeFilesView: View {
    @StateObject private var viewModel = LargeFilesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.files.isEmpty && !viewModel.isScanning {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Large Files")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.scan() }
            } label: {
                Label(viewModel.isScanning ? "Scanning…" : "Scan", systemImage: "magnifyingglass")
            }
            .disabled(viewModel.isScanning)
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
            }
            Spacer()
            Text("Largest files in your home folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No large files yet")
                .font(.title2)
            Text("Scan to find the biggest files in your home folder.")
                .foregroundStyle(.secondary)
            Button("Scan Now") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.files, id: \.url) { file in
                HStack(spacing: 8) {
                    Toggle("", isOn: selectionBinding(for: file.url))
                        .labelsHidden()
                    Image(systemName: "doc")
                        .foregroundStyle(.secondary)
                    Text(file.url.path)
                        .truncationMode(.middle)
                        .lineLimit(1)
                    Spacer()
                    Text(Format.bytes(file.size))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(viewModel.selected.count) selected · \(Format.bytes(viewModel.selectedBytes))")
                if let message = viewModel.message {
                    Text(message).font(.caption).foregroundStyle(.green)
                }
                if let error = viewModel.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            Button {
                viewModel.trashSelected()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selected.isEmpty || viewModel.isTrashing)
        }
        .padding()
        .background(.bar)
    }

    private func selectionBinding(for url: URL) -> Binding<Bool> {
        Binding(
            get: { viewModel.selected.contains(url) },
            set: { isOn in
                if isOn { viewModel.selected.insert(url) }
                else { viewModel.selected.remove(url) }
            }
        )
    }
}
