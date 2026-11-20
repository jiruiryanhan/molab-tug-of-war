import SwiftUI

/// A player as a round dot: coloured border, photo in the middle, initials when there is no photo.
struct PlayerDotView: View {
    var color: Color
    var initials: String
    var image: UIImage?
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.25))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size - size * 0.12, height: size - size * 0.12)
                    .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Circle().stroke(color, lineWidth: max(2, size * 0.08))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
