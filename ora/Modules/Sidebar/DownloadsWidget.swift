import SwiftUI

struct DownloadsWidget: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.theme) private var theme
    @State private var isHovered = false

    var body: some View {
        Button(action: {
            downloadManager.isDownloadsPopoverOpen.toggle()
        }) {
            ZStack {
                // Icon
                Image(systemName: "arrow.down.circle")
                    .foregroundColor(downloadButtonColor)
                    .frame(width: 12, height: 12)
                
                // Circular progress indicator - overlays the circle part of the SF Symbol
                if !downloadManager.activeDownloads.isEmpty, let firstDownload = downloadManager.activeDownloads.first {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    
                    Circle()
                        .trim(from: 0, to: firstDownload.displayProgress)
                        .stroke(.blue, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 12, height: 12)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.2), value: firstDownload.displayProgress)
                }
            }
            .padding(8)
            .background(isHovered ? theme.invertedSolidWindowBackgroundColor.opacity(0.3) : .clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .popover(isPresented: $downloadManager.isDownloadsPopoverOpen, arrowEdge: .bottom) {
            DownloadsListView()
                .environmentObject(downloadManager)
        }
    }

    private var downloadButtonColor: Color {
        if !downloadManager.activeDownloads.isEmpty {
            return .secondary
        } else if downloadManager.recentDownloads.contains(where: { $0.status == .completed }) {
            return .green
        } else {
            return .secondary
        }
    }
}
