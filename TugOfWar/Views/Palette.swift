import SwiftUI

enum Palette {
    static let red = Color(red: 0.93, green: 0.27, blue: 0.27)
    static let blue = Color(red: 0.42, green: 0.32, blue: 0.96)
    static let paper = Color(red: 0.99, green: 0.98, blue: 0.96)

    /// Distinct colours for free-for-all players.
    static let solo: [Color] = [
        Color(red: 0.95, green: 0.45, blue: 0.20),
        Color(red: 0.20, green: 0.70, blue: 0.40),
        Color(red: 0.20, green: 0.60, blue: 0.95),
        Color(red: 0.85, green: 0.30, blue: 0.75),
        Color(red: 0.95, green: 0.75, blue: 0.15),
        Color(red: 0.30, green: 0.75, blue: 0.75),
        Color(red: 0.60, green: 0.40, blue: 0.90),
        Color(red: 0.55, green: 0.65, blue: 0.20),
        Color(red: 0.90, green: 0.35, blue: 0.45),
        Color(red: 0.35, green: 0.45, blue: 0.90),
    ]

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
