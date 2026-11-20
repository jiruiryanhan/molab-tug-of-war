import SwiftUI

/// Team and player colours. These are the system colours, so everything keeps its
/// contrast in light and dark mode and matches the rest of iOS.
enum Palette {
    static let red = Color.red
    static let blue = Color.blue

    /// Distinct colours for free-for-all players, in a fixed order.
    static let solo: [Color] = [.orange, .green, .indigo, .pink, .yellow, .teal, .purple, .mint, .brown, .cyan]

    static func color(team: Team, colorIndex: Int) -> Color {
        switch team {
        case .red: return red
        case .blue: return blue
        case .none:
            let n = solo.count
            return solo[((colorIndex % n) + n) % n]
        }
    }
}
