import SwiftUI

struct LobbyView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app
    @State private var nfc = NFCService()
    @State private var copied = false

    private var reds: [PlayerRecord] { session.players.filter { $0.team == .red } }
    private var blues: [PlayerRecord] { session.players.filter { $0.team == .blue } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        Text(session.isPractice ? "PRACTICE" : "ROOM CODE")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(session.code)
                            .font(.system(size: 46, weight: .black, design: .monospaced))
                            .kerning(8)
                        Text(session.mode.title + (session.mode == .circular ? " · " + (session.meta?.teamMode.title ?? "") : ""))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)

                    if !session.isPractice {
                        HStack(spacing: 10) {
                            ShareLink(item: JoinLink.url(code: session.code),
                                      subject: Text("Join my Tug of War"),
                                      message: Text("Open this on your iPhone to join room \(session.code).")) {
                                Label("AirDrop link", systemImage: "square.and.arrow.up")
                            }
                            Button {
                                UIPasteboard.general.string = session.code
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            if NFCService.isAvailable {
                                Button {
                                    nfc.write(url: JoinLink.url(code: session.code)) { _ in }
                                } label: {
                                    Label("Write tag", systemImage: "wave.3.right")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                    }
                }

                if session.mode == .linear {
                    Section("Red · \(reds.count)") { ForEach(reds) { row($0) } }
                    Section("Blue · \(blues.count)") { ForEach(blues) { row($0) } }
                } else {
                    Section("Players · \(session.players.count)") {
                        ForEach(session.players) { row($0) }
                    }
                    Text(session.meta?.teamMode == .teams
                         ? "Teams and seats are drawn randomly when the host starts."
                         : "Seats are drawn randomly when the host starts.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section {
                    if session.mode == .linear {
                        HStack {
                            Button("Switch team") { session.switchTeam() }
                            if session.isHost {
                                Spacer()
                                Button("Split randomly") { session.shuffleTeams() }
                            }
                        }
                    }
                    if session.isHost {
                        Button {
                            session.startRound()
                        } label: {
                            Label("Start round", systemImage: "flag.checkered")
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!session.canStart)
                        if session.players.count < 2 {
                            Text("Need at least two players.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Waiting for the host to start…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Lobby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave", role: .destructive) { app.leaveRoom() }
                }
            }
        }
        .alert("NFC", isPresented: Binding(get: { nfc.statusMessage != nil }, set: { if !$0 { nfc.statusMessage = nil } })) {
            Button("OK") { nfc.statusMessage = nil }
        } message: {
            Text(nfc.statusMessage ?? "")
        }
    }

    private func row(_ p: PlayerRecord) -> some View {
        HStack(spacing: 12) {
            PlayerDotView(color: Palette.color(team: p.team, colorIndex: p.colorIndex),
                          initials: p.initials, image: session.avatars[p.id], size: 40)
            Text(p.name)
            if p.id == session.myId {
                Text("you").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if p.id == session.meta?.hostId {
                Label("host", systemImage: "crown.fill").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
