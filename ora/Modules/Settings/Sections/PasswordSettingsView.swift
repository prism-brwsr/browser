import SwiftData
import SwiftUI

struct PasswordSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PasswordItem.siteName) private var passwords: [PasswordItem]
    @State private var importResultMessage: String?

    var body: some View {
        SettingsContainer(maxContentWidth: 760) {
            Form {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    importSection
                    listSection
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Passwords")
                .font(.title3.weight(.semibold))
            Text("Prism can store website passwords locally using the macOS Keychain and SwiftData.")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Section {
                Button {
                    importFromChromeCSV()
                } label: {
                    Label("Import from Chrome CSV…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)

                if let message = importResultMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var listSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Section {
                if passwords.isEmpty {
                    Text("No passwords saved yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    List {
                        ForEach(passwords) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.siteName)
                                    .font(.headline)
                                if let host = item.url?.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(item.urlString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.username)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .frame(minHeight: 160)
                }
            }
        }
    }

    private func importFromChromeCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let importer = PasswordImporter()
                    let count = try importer.importChromeCSV(from: url, into: modelContext)
                    importResultMessage = count > 0
                        ? "Imported \(count) passwords from Chrome."
                        : "No passwords were imported."
                } catch {
                    importResultMessage = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}







