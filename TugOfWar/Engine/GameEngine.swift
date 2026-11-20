import Foundation

/// A participant as the simulation sees it.
struct EnginePlayer {
    var id: String
    var team: Team
    var slot: Int
    var pull: Double
    var tugs: Int
}

enum RoundOutcome: Equatable {
    case winner(String)   // "red" | "blue" | player id
    case draw
}

/// Host-authoritative physics. Pure value type: feed it inputs, it advances the state.
struct GameEngine {
    let mode: GameMode
    let teamMode: TeamMode
    let slotCount: Int
    private(set) var state: GameState
    private var lastTugs: [String: Int] = [:]

    init(mode: GameMode, teamMode: TeamMode, slotCount: Int, state: GameState) {
        self.mode = mode
        self.teamMode = teamMode
        self.slotCount = max(slotCount, 1)
        self.state = state
    }

    mutating func step(dt rawDt: Double, players: [EnginePlayer]) -> RoundOutcome? {
        let dt = clamp(rawDt, 0, 0.05)
        state.elapsed += dt
        switch mode {
        case .linear: return stepLinear(dt, players)
        case .circular: return stepCircular(dt, players)
        }
    }

    /// Tug counters are monotonic per round; only count the ones we have not seen yet.
    /// The first sighting is the baseline (already applied by the previous host when this
    /// engine was created on a host hand-over), and the watermark never goes down (a missing
    /// or stale input must not replay a whole round of tugs).
    private mutating func consumeTugs(_ p: EnginePlayer) -> Int {
        guard let prev = lastTugs[p.id] else {
            lastTugs[p.id] = p.tugs
            return 0
        }
        guard p.tugs > prev else { return 0 }
        lastTugs[p.id] = p.tugs
        return p.tugs - prev
    }

    // MARK: - Team Linear

    private mutating func stepLinear(_ dt: Double, _ players: [EnginePlayer]) -> RoundOutcome? {
        var force = 0.0
        var impulse = 0.0
        for p in players where p.slot >= 0 && state.elim[p.id] == nil {
            let dir: Double
            switch p.team {
            case .red: dir = -1
            case .blue: dir = 1
            case .none: continue
            }
            force += dir * p.pull * GameConfig.pullForce
            impulse += dir * Double(consumeTugs(p)) * GameConfig.tugImpulse
        }
        state.vx += impulse + force * dt
        state.vx *= max(0, 1 - GameConfig.damping * dt)
        state.vx = clamp(state.vx, -GameConfig.maxSpeed, GameConfig.maxSpeed)
        state.x += state.vx * dt

        if state.x <= -GameConfig.goalDistance {
            state.x = -GameConfig.goalDistance; state.vx = 0
            return .winner("red")
        }
        if state.x >= GameConfig.goalDistance {
            state.x = GameConfig.goalDistance; state.vx = 0
            return .winner("blue")
        }
        return nil
    }

    // MARK: - Circular

    /// Tug of war on a ring-shaped ledge. Everyone holds one rope, so the rope you win is
    /// rope somebody else loses: a player moves out when they pull harder than the average
    /// of everyone still standing, and in when they pull less. There is a hole in the middle
    /// that keeps growing and a pit outside the ledge, so you can lose at either end.
    private mutating func stepCircular(_ dt: Double, _ players: [EnginePlayer]) -> RoundOutcome? {
        // The hole grows all round, and much faster once the round drags on.
        let rate: Double
        if state.elapsed > GameConfig.holeRushDelay {
            rate = GameConfig.holeRushRate
        } else if state.elapsed > GameConfig.holeGrowDelay {
            rate = GameConfig.holeGrowRate
        } else {
            rate = 0
        }
        state.holeR = min(state.holeR + rate * dt, GameConfig.outerRadius - GameConfig.dotRadius)

        var alive: [EnginePlayer] = []
        var pulls: [Double] = []
        var tugs: [Double] = []
        for p in players where p.slot >= 0 && state.elim[p.id] == nil {
            if state.radii[p.id] == nil { state.radii[p.id] = GameConfig.startRadius }
            alive.append(p)
            pulls.append(p.pull)
            tugs.append(Double(consumeTugs(p)))
        }
        guard !alive.isEmpty else { return .draw }

        let meanPull = pulls.reduce(0, +) / Double(alive.count)
        let meanTug = tugs.reduce(0, +) / Double(alive.count)

        for (i, p) in alive.enumerated() {
            var v = state.radVel[p.id] ?? 0
            v += (tugs[i] - meanTug) * GameConfig.radialTug
            v += (pulls[i] - meanPull) * GameConfig.radialForce * dt
            v *= max(0, 1 - GameConfig.radialDamping * dt)
            v = clamp(v, -GameConfig.maxRadialSpeed, GameConfig.maxRadialSpeed)
            state.radVel[p.id] = v
            state.radii[p.id] = state.radius(p.id) + v * dt
        }

        // Out at either end: swallowed by the hole, or dragged off the outer edge.
        let edge = GameConfig.dotRadius * 0.4
        for p in alive {
            let r = state.radius(p.id)
            if r <= state.holeR + edge || r >= GameConfig.outerRadius - edge {
                state.elim[p.id] = state.elapsed
                state.radVel[p.id] = 0
                state.radii[p.id] = clamp(r, state.holeR, GameConfig.outerRadius)
            }
        }

        let remaining = alive.filter { state.elim[$0.id] == nil }
        switch teamMode {
        case .teams:
            let reds = remaining.filter { $0.team == .red }.count
            let blues = remaining.filter { $0.team == .blue }.count
            if reds == 0 && blues == 0 { return .draw }
            if reds == 0 { return .winner("blue") }
            if blues == 0 { return .winner("red") }
        case .individual:
            if remaining.isEmpty { return .draw }
            if remaining.count == 1 { return .winner(remaining[0].id) }
        }
        return nil
    }
}
