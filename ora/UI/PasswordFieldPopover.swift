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
        let domainMatches = items.filter { item in
            guard let itemHost = item.url?.host else { return false }
            return PasswordFieldPopover.baseDomain(from: itemHost) == PasswordFieldPopover.baseDomain(from: host)
        }
        
        // Filter by input value if present
        let filterText = tab.passwordFieldInputValue.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filterText.isEmpty else { return domainMatches }
        
        return domainMatches.filter { item in
            item.username.lowercased().contains(filterText)
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
                                            Text(item.username)
                                                .font(.system(size: 12, weight: .medium))
                                                .lineLimit(1)
                                            Text(item.siteName)
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
        await tab.fillPassword(from: item)
    }
}

