import SwiftUI
import Combine

/// View model for the Settings screen (threshold + whitelist handled by WhitelistView).
final class SettingsViewModel: ObservableObject {
    @Published var thresholdText: String
    @Published var savedThresholdMB: Int64

    private let store = SettingsStore()

    init() {
        let bytes = store.load().largeFileThresholdBytes
        let mb = max(1, bytes / (1024 * 1024))
        savedThresholdMB = mb
        thresholdText = String(mb)
    }

    func saveThreshold() {
        guard let mb = Int64(thresholdText.trimmingCharacters(in: .whitespacesAndNewlines)), mb > 0 else {
            return
        }
        try? store.setLargeFileThreshold(bytes: mb * 1024 * 1024)
        savedThresholdMB = mb
        thresholdText = String(mb)
    }
}

/// Preferences: large-file threshold and protected paths (whitelist).
struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Large file threshold") {
                    HStack(spacing: 8) {
                        TextField("Megabytes", text: $viewModel.thresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 140)
                        Text("MB")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { viewModel.saveThreshold() }
                    }
                    .padding(6)
                }

                GroupBox("Protected paths (whitelist)") {
                    WhitelistView()
                }
            }
            .padding()
        }
        .navigationTitle("Settings")
    }
}
