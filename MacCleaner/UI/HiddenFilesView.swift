import SwiftUI
import Combine

/// One parent directory and the hidden items found directly beneath it.
struct HiddenGroup: Identifiable {
    let parent: URL
    var children: [URL]
    var id: URL { parent }
}

/// View model for the Hidden Files feature.
@MainActor
final class HiddenFilesViewModel: ObservableObject {
    @Published var groups: [HiddenGroup] = []
    @Published var selected: Set<URL> = []
    @Published var isScanning = false
    @Published var isTrashing = false
    @Published var message: String?
    @Published var errorMessage: String?

    private let log = OperationLog()

    var selectedBytes: Int64 {
        groups.flatMap { $0.children }
            .filter { selected.contains($0) }
            .reduce(0) { $0 + Cleaner.fileSize($1) }
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        message = nil
        errorMessage = nil
        let home = FileManager.default.homeDirectoryForCurrentUser
        let detected = await Task.detached(priority: .userInitiated) {
            HiddenFileDetector().detect(root: home, maxDepth: 8)
        }.value
        groups = detected
            .map { HiddenGroup(parent: $0.key, children: $0.value.sorted { $0.path < $1.path }) }
            .sorted { $0.parent.path < $1.parent.path }
        selected.removeAll()
    }

    func trashSelected() {
        let urls = groups.flatMap { $0.children }.filter { selected.contains($0) }
        guard !urls.isEmpty else { return }
        isTrashing = true
        defer { isTrashing = false }
        message = nil
        errorMessage = nil
        do {
            let moved = try Cleaner.trash(urls: urls, log: log)
            message = "Moved \(moved.count) of \(urls.count) hidden items to Trash."
            let removed = Set(urls)
            for index in groups.indices {
                groups[index].children.removeAll { removed.contains($0) }
            }
            groups.removeAll { $0.children.isEmpty }
            selected.removeAll()
        } catch {
            errorMessage = "\(error)"
        }
    }
}

/// Lists hidden files/directories grouped by their parent directory.
struct HiddenFilesView: View {
    @StateObject private var viewModel = HiddenFilesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.groups.isEmpty && !viewModel.isScanning {
                emptyState
            } else {
                list
            }
        }
        .navigationTitle("Hidden Files")
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
            Text("Hidden items in your home folder")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "eye.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No hidden items found")
                .font(.title2)
            Text("Scan to find dotfiles and other hidden items.")
                .foregroundStyle(.secondary)
            Button("Scan Now") { Task { await viewModel.scan() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(viewModel.groups) { group in
                Section(group.parent.path) {
                    ForEach(group.children, id: \.self) { url in
                        HStack(spacing: 8) {
                            Toggle("", isOn: selectionBinding(for: url))
                                .labelsHidden()
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                            Spacer()
                            Text(Format.bytes(Cleaner.fileSize(url)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
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
