import SwiftData
import SwiftUI

struct ContainerSwitcher: View {
    let onContainerSelected: (TabContainer) -> Void

    @Environment(\.theme) private var theme
    @EnvironmentObject var tabManager: TabManager
    @Query(sort: ContainerConstants.sortDescriptors) var containers: [TabContainer]

    @State private var hoveredContainer: UUID?
    @State private var editingContainer: TabContainer?
    @State private var isEditModalOpen = false
    @State private var orderedContainers: [TabContainer] = []
    @State private var activeDragId: UUID?
    @State private var activeDragTranslation: CGSize = .zero
    @State private var dragStartIndex: Int?
    @State private var dragStep: CGFloat = ContainerConstants.UI.normalButtonWidth

    var body: some View {
        GeometryReader { geometry in
            let activeContainers = orderedContainers.isEmpty ? containers : orderedContainers
            let availableWidth = geometry.size.width
            let totalWidth =
                CGFloat(activeContainers.count) * ContainerConstants.UI.normalButtonWidth + CGFloat(max(
                    0,
                    activeContainers.count - 1
                ))
                * 2
            let isCompact = totalWidth > availableWidth
            let spacing = isCompact ? 4.0 : 2.0
            let baseButtonWidth = isCompact ? ContainerConstants.UI.compactButtonWidth : ContainerConstants.UI.normalButtonWidth
            let buttonStep = baseButtonWidth + spacing

            HStack(alignment: .center, spacing: spacing) {
                ForEach(activeContainers, id: \.id) { container in
                    containerButton(for: container, isCompact: isCompact)
                        .offset(x: activeDragId == container.id ? activeDragTranslation.width : 0)
                        .zIndex(activeDragId == container.id ? 1 : 0)
                        .highPriorityGesture(dragGesture(for: container, step: buttonStep))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(0)
        }
        .padding(0)
        .frame(height: 28)
        .popover(isPresented: $isEditModalOpen) {
            if let container = editingContainer {
                EditContainerModal(
                    container: container,
                    isPresented: $isEditModalOpen
                )
            }
        }
        .onAppear {
            orderedContainers = containers
        }
        .onChange(of: containers) { newContainers in
            guard activeDragId == nil else { return }
            orderedContainers = newContainers
        }
    }

    @ViewBuilder
    private func containerButton(for container: TabContainer, isCompact: Bool)
        -> some View
    {
        let isActive = tabManager.activeContainer?.id == container.id
        let isHovered = hoveredContainer == container.id
        let isDragging = activeDragId == container.id
        let displayEmoji = isCompact && !isActive ? (isHovered ? container.emoji : ContainerConstants.defaultEmoji) :
            container.emoji
        let buttonSize = isCompact && !isActive ?
            (isHovered ? ContainerConstants.UI.compactButtonWidth + 4 : ContainerConstants.UI.compactButtonWidth) :
            ContainerConstants.UI.normalButtonWidth
        let fontSize: CGFloat = isCompact && !isActive ?
            (isHovered ? (container.emoji == ContainerConstants.defaultEmoji ? 24 : 12) : 12
            ) :
            (container.emoji == ContainerConstants.defaultEmoji ? 24 : 12)

        Button(action: {
            guard activeDragId == nil else { return }
            onContainerSelected(container)
        }) {
            HStack {
                Text(displayEmoji)
                    .font(.system(size: fontSize))
                    .foregroundColor(displayEmoji == ContainerConstants.defaultEmoji ? .primary : .secondary)
            }
            .frame(width: buttonSize, height: buttonSize)
            .grayscale(!isActive && !isHovered ? 0.5 : 0)
            .opacity(!isActive ? 0.5 : 1)
            .background(
                !isCompact && isHovered
                    ? theme.invertedSolidWindowBackgroundColor.opacity(0.3)
                    : isActive
                    ? theme.invertedSolidWindowBackgroundColor.opacity(0.2)
                    : .clear
            )
            .cornerRadius(8)
            .opacity(isDragging ? 0.3 : 1)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: isActive || isHovered)
        .onHover { isHovering in
            guard activeDragId == nil else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredContainer = isHovering ? container.id : nil
            }
        }
        .contextMenu {
            Button("Edit Space") {
                editingContainer = container
                isEditModalOpen = true
            }
            Button("Delete Space") {
                tabManager.deleteContainer(container)
            }
            .disabled(containers.count == 1) // disabled to avoid crashes
        }
    }

    private func dragGesture(for container: TabContainer, step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if activeDragId == nil {
                    activeDragId = container.id
                    activeDragTranslation = .zero
                    dragStartIndex = orderedContainers.firstIndex(where: { $0.id == container.id })
                    dragStep = max(step, 1)
                }
                guard activeDragId == container.id else { return }
                activeDragTranslation = value.translation
                updateOrder(for: container)
            }
            .onEnded { _ in
                guard activeDragId == container.id else { return }
                persistCurrentOrder(orderedContainers)
                activeDragId = nil
                dragStartIndex = nil
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    activeDragTranslation = .zero
                }
            }
    }

    private func updateOrder(for container: TabContainer) {
        guard let startIndex = dragStartIndex,
              let currentIndex = orderedContainers.firstIndex(where: { $0.id == container.id }),
              dragStep > 0 else { return }

        let rawOffset = activeDragTranslation.width / dragStep
        let offset = Int(rawOffset.rounded())
        let targetIndex = clamp(startIndex + offset, min: 0, max: orderedContainers.count - 1)

        guard targetIndex != currentIndex else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            let item = orderedContainers.remove(at: currentIndex)
            orderedContainers.insert(item, at: targetIndex)
        }
        let snappedOffset = CGFloat(targetIndex - startIndex) * dragStep
        activeDragTranslation.width -= snappedOffset
    }

    private func persistCurrentOrder(_ order: [TabContainer]) {
        tabManager.persistContainerOrder(order)
        orderedContainers = order
    }

    private func clamp(_ value: Int, min: Int, max: Int) -> Int {
        if value < min { return min }
        if value > max { return max }
        return value
    }
}
