//
//  ExtensionsSettingsView.swift
//  ora
//
//  Settings view for managing browser extensions
//

import SwiftUI

struct ExtensionsSettingsView: View {
    @State private var extensionManager = ExtensionManager.shared
    @State private var showingInstallSheet = false
    @State private var installError: String?
    
    var body: some View {
        SettingsContainer(maxContentWidth: 760) {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Extensions")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Install and manage browser extensions to customize your browsing experience")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Install button
                HStack {
                    Button(action: { showingInstallSheet = true }) {
                        Label("Install Extension", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Spacer()
                }
                
                // Extensions list
                if extensionManager.extensions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Extensions Installed")
                            .font(.headline)
                        Text("Click \"Install Extension\" to add your first extension")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(extensionManager.extensions) { ext in
                            ExtensionRow(ext: ext)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingInstallSheet) {
            InstallExtensionSheet(
                onInstall: { url in
                    do {
                        try extensionManager.installExtension(from: url)
                        installError = nil
                        showingInstallSheet = false
                    } catch {
                        installError = error.localizedDescription
                    }
                },
                error: installError
            )
        }
    }
}

struct ExtensionRow: View {
    let ext: BrowserExtension
    @State private var extensionManager = ExtensionManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon placeholder
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(ext.name)
                        .font(.headline)
                    
                    Text("v\(ext.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(4)
                }
                
                if let description = ext.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                if let author = ext.author {
                    Text("by \(author)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { ext.isEnabled },
                    set: { _ in extensionManager.toggleExtension(ext) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                
                Button(action: {
                    do {
                        try extensionManager.uninstallExtension(ext)
                    } catch {
                        // Handle error
                    }
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Uninstall extension")
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }
}

struct InstallExtensionSheet: View {
    let onInstall: (URL) -> Void
    let error: String?
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Install Extension")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Select an extension folder or zip file to install")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
            }
            
            Button("Choose Extension...") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = true
                panel.allowedContentTypes = [.zip]
                panel.canCreateDirectories = false
                
                if panel.runModal() == .OK, let url = panel.url {
                    selectedURL = url
                    onInstall(url)
                }
            }
            .buttonStyle(.borderedProminent)
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(width: 400)
    }
}

