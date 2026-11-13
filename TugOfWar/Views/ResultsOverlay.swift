import SwiftUI

struct ResultsOverlay: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app

    private var winner: String? { session.meta?.winner }

    private var title: String {
        switch winner {
        case "red": return "RED WINS!"
        case "blue": return "BLUE WINS!"
        case "draw", nil: return "DRAW"
        case let id?: return (session.player(id)?.name ?? "Someone") + " WINS!"
        }
    }

    private var iWon: Bool {
        guard let winner, let me = session.me else { return false }
        return winner == me.id || (me.team != .none && winner == me.team.rawValue)
    }

    private var titleColor: Color {
        switch winner {
        case "red": return Palette.red
        case "blue": return Palette.blue
        case let id?: if let p = session.player(id) { return Palette.color(team: p.team, colorIndex: p.colorIndex) }
            return .primary
        default: return .primary
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.center)
            if session.amParticipating {
                Text(iWon ? "You win! 🎉" : (winner == "draw" ? "Everyone fell in." : "Better luck next round."))
                    .font(.headline)
            }
            if session.isHost {
                Button {
                    session.startRound()
                } label: {
                    Label("Play again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!session.canStart)
                Button("Back to lobby") { session.backToLobby() }
                    .buttonStyle(.bordered)
            } else {
                Label("Waiting for the host…", systemImage: "hourglass")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Button("Leave room", role: .destructive) { app.leaveRoom() }
                .font(.subheadline)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .shadow(radius: 20)
        .transition(.scale.combined(with: .opacity))
    }
}
