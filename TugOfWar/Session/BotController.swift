import Foundation

/// Practice opponents. Bots are ordinary players as far as the room is concerned: they
/// get a player record and write their own `inputs/{id}` through the same transport.
@MainActor
final class BotController {
    let transport: RoomTransport
    let code: String
    private(set) var ids: [String] = []

    /// Set by the session so a bot on the ring can tell where it is standing.
    var radiusProvider: ((String) -> Double?)?
    var holeProvider: (() -> Double)?

    private var pulls: [String: Double] = [:]
    private var targets: [String: Double] = [:]
    private var nerve: [String: Double] = [:]
    private var bias: [String: Double] = [:]
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
            nerve[id] = Double.random(in: 0.75...1.1)   // how hard this bot likes to pull
            bias[id] = Double.random(in: -70...70)      // where on the ledge it likes to stand
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
                targets[id] = aim(id)
                nextTarget[id] = now + Double.random(in: 0.5...1.4)
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

    /// On the ring a bot digs in when the hole gets close and eases off near the outer
    /// edge, so it does not pull itself over the brink.
    private func aim(_ id: String) -> Double {
        let base = nerve[id] ?? 1
        guard let r = radiusProvider?(id) else {
            return clamp(Double.random(in: 0.25...0.95) * base, 0, 1)
        }
        let hole = holeProvider?() ?? GameConfig.holeStartRadius
        // Each bot likes its own spot on the ledge, so the field spreads out and the hole
        // catches the hindmost rather than everyone at once.
        let safe = GameConfig.bandMiddle(hole: hole) + (bias[id] ?? 0)
        let room = max(GameConfig.outerRadius - hole, 1)
        // 1 when hugging the hole, 0 when hugging the outer edge.
        let danger = clamp((safe - r) / (room / 2), -1, 1)
        let wanted = 0.5 + 0.45 * danger + Double.random(in: -0.12...0.12)
        return clamp(wanted * base, 0, 1)
    }

    func stop() {
        ids = []
    }
}
