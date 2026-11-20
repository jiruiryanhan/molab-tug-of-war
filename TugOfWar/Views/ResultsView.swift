import SwiftUI

/// Shown as a half-height sheet when a round ends. The field stays visible behind it.
struct ResultsView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app

    private var winner: String? { session.meta?.winner }

    private var iWon: Bool {
        guard let winner, let me = session.me else { return false }
        return winner == me.id || (me.team != .none && winner == me.team.rawValue)
    }

    private var title: String {
        switch winner {
        case "red": return "Red Wins"
        case "blue": return "Blue Wins"
        case "draw", nil: return "Draw"
        case let id?: return "\(session.player(id)?.name ?? "Someone") Wins"
        }
    }

    private var subtitle: String {
        if !session.amParticipating { return "You are in the next round." }
        if winner == "draw" { return "Everyone fell in." }
        return iWon ? "Nice pull." : "Better luck next round."
    }

    private var accent: Color {
        switch winner {
        case "red": return Palette.red
        case "blue": return Palette.blue
        case "draw", nil: return .secondary
        case let id?:
            guard let p = session.player(id) else { return .accentColor }
            return Palette.color(team: p.team, colorIndex: p.colorIndex)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                Image(systemName: iWon ? "trophy.fill" : "flag.checkered")
                    .font(.system(size: 48))
                    .foregroundStyle(accent)
                    .symbolRenderingMode(.hierarchical)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.largeTitle.bold())
                    Text(subtitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                if session.isHost {
                    VStack(spacing: 10) {
                        Button {
                            session.startRound()
                        } label: {
                            Text("Play Again")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!session.canStart)

                        Button("Back to Lobby") { session.backToLobby() }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    Label("Waiting for the host…", systemImage: "hourglass")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Leave") { app.leaveRoom() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
    }
}
