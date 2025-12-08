import SwiftUI

struct RenameTabModal: View {
    let tab: Tab
    @Binding var isPresented: Bool

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager

    @State private var customName: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            nameTextField
            actionButtons
        }
        .frame(width: 320)
        .padding()
        .onAppear {
            setupInitialValues()
        }
    }

    private var headerView: some View {
        Text("Rename Tab")
            .font(.headline)
    }

    private var nameTextField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tab Name")
                .font(.subheadline)
                .foregroundColor(theme.foreground.opacity(0.7))
            
            TextField("Enter custom name", text: $customName)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .focused($isTextFieldFocused)
                .onSubmit {
                    saveRename()
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isTextFieldFocused ? theme.foreground.opacity(0.5) : theme.border,
                            lineWidth: isTextFieldFocused ? 2 : 1
                        )
                )
            
            Text("Leave empty to use the page title")
                .font(.caption)
                .foregroundColor(theme.foreground.opacity(0.5))
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)
            
            Button("Save") {
                saveRename()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tab.customName == nil)
        }
    }

    private func setupInitialValues() {
        customName = tab.customName ?? ""
        // Focus the text field after a small delay to ensure it's visible
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
            // Select all text if there's a custom name
            if !customName.isEmpty {
                // Text selection would need NSTextField, but for now just focus is fine
            }
        }
    }

    private func saveRename() {
        let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? nil : trimmed
        tabManager.renameTab(tab, customName: finalName)
        isPresented = false
    }
}



