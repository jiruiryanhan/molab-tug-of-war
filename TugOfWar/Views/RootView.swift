import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let session = app.session {
                RoomView(session: session)
                    .id(session.code)
            } else {
                HomeView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.session?.code)
    }
}

/// Lobby while waiting, the arena once a round is on.
struct RoomView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch session.status {
            case .lobby:
                LobbyView(session: session)
            case .countdown, .playing, .finished:
                GameView(session: session)
            }
        }
        .onChange(of: session.closed) { _, closed in
            if closed {
                app.errorMessage = session.errorMessage
                app.leaveRoom()
            }
        }
    }
}
