//
//  ExtensionsMenuButton.swift
//  ora
//
//  Extensions menu button for the URL bar
//

import SwiftUI

struct ExtensionsMenuButton: View {
    let foregroundColor: Color
    @State private var extensionManager = ExtensionManager.shared
    @State private var isMenuPresented = false
    
    private var enabledExtensions: [BrowserExtension] {
        extensionManager.extensions.filter { $0.isEnabled }
    }
    
    var body: some View {
        if !enabledExtensions.isEmpty {
            URLBarButton(
                systemName: "puzzlepiece.extension.fill",
                isEnabled: true,
                foregroundColor: foregroundColor,
                action: {
                    isMenuPresented.toggle()
                }
            )
            .popover(isPresented: $isMenuPresented, arrowEdge: .bottom) {
                ExtensionsMenuView(extensions: enabledExtensions)
            }
        }
    }
}

struct ExtensionsMenuView: View {
    let extensions: [BrowserExtension]
    @State private var extensionManager = ExtensionManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Extensions")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    dismiss()
                    // Open extensions settings
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("selectExtensionsTab"),
                            object: nil
                        )
                    }
                }) {
                    Text("Manage")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Extensions list
            if extensions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No enabled extensions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(extensions) { ext in
                            ExtensionMenuItem(ext: ext)
                            if ext.id != extensions.last?.id {
                                Divider()
                                    .padding(.leading, 44)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(width: 300)
    }
}

struct ExtensionMenuItem: View {
    let ext: BrowserExtension
    @State private var extensionManager = ExtensionManager.shared
    @State private var isHovered = false
    @State private var showPopup = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Extension icon placeholder
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.blue.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(ext.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                if let description = ext.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("v\(ext.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Options menu
            Menu {
                if ext.popupPath != nil {
                    Button("Open Popup") {
                        showPopup = true
                    }
                }
                
                if ext.optionsPage != nil {
                    Button("Options") {
                        // TODO: Open extension options page
                    }
                }
                
                if ext.popupPath != nil || ext.optionsPage != nil {
                    Divider()
                }
                
                Button("Remove") {
                    do {
                        try extensionManager.uninstallExtension(ext)
                    } catch {
                        // Handle error
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(isHovered ? Color.secondary.opacity(0.2) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0.3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isHovered ? Color(NSColor.controlBackgroundColor).opacity(0.5) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            // If extension has a popup, show it on click
            if ext.popupPath != nil {
                showPopup = true
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $showPopup, arrowEdge: .leading) {
            if let popupPath = ext.popupPath {
                ExtensionPopupView(ext: ext, popupPath: popupPath)
            }
        }
    }
}

