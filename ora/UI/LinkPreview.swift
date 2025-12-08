import SwiftUI

struct LinkPreview: View {
    let text: String
    @Environment(\.theme) private var theme

    var body: some View {
        VStack {
            Spacer()
            HStack {
                ZStack {
                    Text(text)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(theme.foreground)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 99, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 99, style: .continuous)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                )
                
                Spacer()
            }
            .padding(.bottom, 8)
            .padding(.leading, 8)
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.1), value: text)
        .zIndex(900)
    }
}
