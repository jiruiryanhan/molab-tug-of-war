import Foundation

/// Practice opponents. Bots are ordinary players as far as the room is concerned: they
/// get a player record and write their own `inputs/{id}` through the same transport.
@MainActor
final class BotController {
    let transport: RoomTransport
    let code: String
    private(set) var ids: [String] = []
    private var pulls: [String: Double] = [:]
    private var targets: [String: Double] = [:]
    private var tugs: [String: Int] = [:]
    private var nextTug: [String: TimeInterval] = [:]
    private var nextTarget: [String: TimeInterval] = [:]
    private var lastWrite: TimeInterval = 0
    private var wasPlaying = false

    static let names = ["Ada", "Bo", "Cy", "Dee", "Eli", "Flo", "Gus", "Hal", "Ivy", "Jo", "Kai", "Lu", "Mo", "Nia", "Ox"]

    init(transport: RoomTransport, code: String) {
        self.transport = transport
        self.code = code
    }

    func join(count: Int, mode: GameMode, myTeam: Team) {
        for i in 0..<count {
            let id = "bot-\(i)"
            var team = Team.none
            if mode == .linear {
                team = i % 2 == 0 ? myTeam.other : myTeam
            }
            let rec = PlayerRecord(id: id, name: "Bot " + Self.names[i % Self.names.count], photo: nil,
                                   team: team, slot: -1, colorIndex: team == .blue ? 1 : 0,
                                   joinedAt: transport.serverNow + Double(i + 1))
            transport.set(RoomPaths.player(code, id), value: RTCodec.encode(rec))
            ids.append(id)
        }
    }

    func tick(now: TimeInterval, playing: Bool) {
        if playing && !wasPlaying {
            // New round: the host zeroed inputs/{id}; start our counters from zero too.
            pulls = [:]; tugs = [:]; nextTug = [:]; nextTarget = [:]
        }
        wasPlaying = playing
        guard playing, now - lastWrite >= 0.1 else { return }
        lastWrite = now

        var updates: [String: Any] = [:]
        for id in ids {
            if now >= (nextTarget[id] ?? 0) {
                targets[id] = Double.random(in: 0.25...0.95)
                nextTarget[id] = now + Double.random(in: 0.8...2.0)
            }
            let p = pulls[id] ?? 0
            let t = targets[id] ?? 0.5
            pulls[id] = p + (t - p) * 0.25
            if let due = nextTug[id] {
                if now >= due {
                    tugs[id, default: 0] += 1
                    nextTug[id] = now + Double.random(in: 0.6...1.6)
                }
            } else {
                nextTug[id] = now + Double.random(in: 0.3...1.2)
            }
            let input = PlayerInput(pull: pulls[id] ?? 0, tugs: tugs[id] ?? 0, t: transport.serverNow)
            updates[RoomPaths.input(code, id)] = RTCodec.encode(input)
        }
        transport.update(updates)
    }

    func stop() {
        ids = []
    }
}
