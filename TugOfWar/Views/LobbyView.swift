import SwiftUI

struct LobbyView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app
    @State private var nfc = NFCService()
    @State private var copied = false

    private var reds: [PlayerRecord] { session.players.filter { $0.team == .red } }
    private var blues: [PlayerRecord] { session.players.filter { $0.team == .blue } }

    private var arenaName: String {
        session.mode == .circular
            ? "\(session.mode.title) · \(session.meta?.teamMode.title ?? "")"
            : session.mode.title
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 4) {
                        Text(session.code)
                            .font(.system(.largeTitle, design: .monospaced, weight: .semibold))
                            .kerning(6)
                            .textSelection(.enabled)
                        Text(arenaName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                } footer: {
                    if !session.isPractice {
                        Text("Friends join with this code, an AirDropped link, or an NFC tag.")
                    }
                }

                if !session.isPractice {
                    Section {
                        ShareLink(item: JoinLink.url(code: session.code),
                                  subject: Text("Join my Tug of War"),
                                  message: Text("Open this on your iPhone to join room \(session.code).")) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = session.code
                            copied = true
                        } label: {
                            Label(copied ? "Copied" : "Copy Code",
                                  systemImage: copied ? "checkmark" : "doc.on.doc")
                        }
                        if NFCService.isAvailable {
                            Button {
                                nfc.write(url: JoinLink.url(code: session.code)) { _ in }
                            } label: {
                                Label("Write NFC Tag", systemImage: "wave.3.right")
                            }
                            .disabled(nfc.isBusy)
                        }
                    }
                }

                if session.mode == .linear {
                    Section("Red · \(reds.count)") { ForEach(reds, content: row) }
                    Section("Blue · \(blues.count)") { ForEach(blues, content: row) }
                } else {
                    Section {
                        ForEach(session.players, content: row)
                    } header: {
                        Text("Players · \(session.players.count)")
                    } footer: {
                        Text(session.meta?.teamMode == .teams
                             ? "Teams and seats are drawn randomly when the round starts."
                             : "Seats are drawn randomly when the round starts.")
                    }
                }

                if session.mode == .linear {
                    Section {
                        Button("Switch My Team") { session.switchTeam() }
                        if session.isHost {
                            Button("Split Teams Randomly") { session.shuffleTeams() }
                        }
                    }
                }

                Section {
                    if session.isHost {
                        Button {
                            session.startRound()
                        } label: {
                            Text("Start Round")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!session.canStart)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    } else {
                        Label("Waiting for the host to start…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if session.isHost && session.players.count < 2 {
                        Text("At least two players are needed.")
                    }
                }
            }
            .navigationTitle("Lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") { app.leaveRoom() }
                }
            }
        }
        .alert("NFC", isPresented: Binding(get: { nfc.statusMessage != nil },
                                           set: { if !$0 { nfc.statusMessage = nil } })) {
            Button("OK") { nfc.statusMessage = nil }
        } message: {
            Text(nfc.statusMessage ?? "")
        }
    }

    private func row(_ p: PlayerRecord) -> some View {
        HStack(spacing: 12) {
            PlayerDotView(color: Palette.color(team: p.team, colorIndex: p.colorIndex),
                          initials: p.initials, image: session.avatars[p.id], size: 36)
            Text(p.name)
            Spacer()
            if p.id == session.myId {
                Text("You").foregroundStyle(.secondary)
            }
            if p.id == session.meta?.hostId {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Host")
            }
        }
    }
}
