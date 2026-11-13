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

    var ringRadius: Double { Layout.ringRadius(count: slotCount) }

    mutating func step(dt rawDt: Double, players: [EnginePlayer]) -> RoundOutcome? {
        let dt = clamp(rawDt, 0, 0.05)
        state.elapsed += dt
        switch mode {
        case .linear: return stepLinear(dt, players)
        case .circular: return stepCircular(dt, players)
        }
    }

    /// Tug counters are monotonic per round; only count the ones we have not seen yet.
    private mutating func consumeTugs(_ p: EnginePlayer) -> Int {
        guard let prev = lastTugs[p.id] else {
            lastTugs[p.id] = p.tugs
            return p.tugs > 0 && p.tugs <= 3 ? p.tugs : 0
        }
        lastTugs[p.id] = p.tugs
        return max(0, p.tugs - prev)
    }

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

    private mutating func stepCircular(_ dt: Double, _ players: [EnginePlayer]) -> RoundOutcome? {
        let r = ringRadius
        var fx = 0.0, fy = 0.0, ix = 0.0, iy = 0.0
        var alive: [EnginePlayer] = []
        for p in players where p.slot >= 0 && state.elim[p.id] == nil {
            alive.append(p)
            let u = Layout.outward(slot: p.slot, count: slotCount)
            fx += u.dx * p.pull * GameConfig.pullForce
            fy += u.dy * p.pull * GameConfig.pullForce
            let n = Double(consumeTugs(p))
            ix += u.dx * n * GameConfig.tugImpulse
            iy += u.dy * n * GameConfig.tugImpulse
        }
        // The knot is elastic: it drifts back toward the hole when nobody is winning.
        fx -= state.x * GameConfig.ringSpring
        fy -= state.y * GameConfig.ringSpring

        state.vx += ix + fx * dt
        state.vy += iy + fy * dt
        let damp = max(0, 1 - GameConfig.damping * dt)
        state.vx *= damp; state.vy *= damp
        let speed = hypot(state.vx, state.vy)
        if speed > GameConfig.maxSpeed {
            state.vx *= GameConfig.maxSpeed / speed
            state.vy *= GameConfig.maxSpeed / speed
        }
        state.x += state.vx * dt
        state.y += state.vy * dt

        // Sudden death: the hole slowly grows so a stalemate always ends.
        if state.elapsed > GameConfig.holeGrowDelay {
            state.holeR = min(state.holeR + GameConfig.holeGrowRate * dt, r + GameConfig.dotRadius)
        }

        // Out when dragged too far off your base, or when the (growing) hole reaches you.
        let limit = Layout.dragLimit(count: slotCount)
        for p in alive {
            let drag = Layout.circularDrag(slot: p.slot, count: slotCount, knot: state.knot)
            let pos = Layout.circularPosition(slot: p.slot, count: slotCount, knot: state.knot)
            if drag > limit || hypot(pos.x, pos.y) < state.holeR + GameConfig.dotRadius * 0.4 {
                state.elim[p.id] = state.elapsed
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
