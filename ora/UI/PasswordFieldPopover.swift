import SwiftData
import SwiftUI

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PasswordFieldPopover: View {
    let host: String
    let tab: Tab
    let items: [PasswordItem]
    let fieldRect: CGRect

    @State private var isExpanded = false
    @State private var showAllItems = false

    private var matches: [PasswordItem] {
        items.filter { item in
            guard let itemHost = item.url?.host else { return false }
            return PasswordFieldPopover.baseDomain(from: itemHost) == PasswordFieldPopover.baseDomain(from: host)
        }
    }

    var body: some View {
        if matches.isEmpty {
            EmptyView()
        } else {
            GeometryReader { geometry in
                let popoverX = fieldRect.midX
                let chipTopY = fieldRect.maxY + 4 // Top edge of chip, 4pt below input field
                let chipHeight: CGFloat = 24 // Chip height
                let chipCenterY = chipTopY + chipHeight / 2 // Center of chip for positioning
                let listTopY = chipTopY + chipHeight + 4 // Top edge of list, 4pt below chip

                ZStack(alignment: .topLeading) {
                    // Chip button - only shown when list is not expanded
                    if !isExpanded {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 12))
                                Text("\(matches.count) password\(matches.count == 1 ? "" : "s")")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.regularMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .position(x: popoverX, y: chipCenterY)
                    }

                    // List - positioned with top edge at listTopY, replaces chip when expanded
                    if isExpanded {
                        let displayedItems = showAllItems ? matches : Array(matches.prefix(8))
                        
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedItems) { item in
                                Button {
                                    Task {
                                        await fill(item: item)
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            isExpanded = false
                                            showAllItems = false
                                        }
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.siteName)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Text(item.username)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                if item.id != displayedItems.last?.id {
                                    Divider()
                                        .opacity(0.2)
                                        .padding(.horizontal, 4)
                                }
                            }
                            
                            if !showAllItems && matches.count > 8 {
                                Divider()
                                    .opacity(0.2)
                                    .padding(.horizontal, 4)
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        showAllItems = true
                                    }
                                } label: {
                                    HStack {
                                        Text("+ \(matches.count - 8) more")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(width: 240)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                        .offset(x: popoverX - 120, y: chipTopY) // Position at same Y as chip would be, replacing it
                    }
                }
            }
            .allowsHitTesting(true)
        }
    }

    private static func baseDomain(from host: String) -> String {
        let components = host.split(separator: ".")
        guard components.count >= 2 else { return host }
        let base = components.suffix(2)
        return base.joined(separator: ".")
    }

    private func fill(item: PasswordItem) async {
        let reason = "Authenticate to fill the selected password in Prism"
        let authenticated = await PasswordKeychain.authenticateForFilling(reason: reason)
        guard authenticated,
              let password = try? PasswordKeychain.loadPassword(for: item.keychainID)
        else {
            return
        }

        let usernameJSON = (try? JSONEncoder().encode(item.username)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        let passwordJSON = (try? JSONEncoder().encode(password)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""

        let js = """
        (function(u, p) {
            function setInput(el, val) {
                if (!el) return;
                el.focus();
                el.value = val;
                el.dispatchEvent(new Event('input', { bubbles: true }));
                el.dispatchEvent(new Event('change', { bubbles: true }));
            }
            var pass = document.querySelector('input[type="password"]');
            if (!pass) return;
            var form = pass.form || document;
            var user = form.querySelector('input[type="email"], input[type="text"], input[name*="user" i], input[name*="mail" i], input[id*="user" i], input[id*="mail" i]');
            setInput(user, u);
            setInput(pass, p);
        })(\(usernameJSON), \(passwordJSON));
        """

        tab.webView.evaluateJavaScript(js, completionHandler: nil)
    }
}

