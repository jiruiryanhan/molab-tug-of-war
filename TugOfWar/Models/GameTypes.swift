import Foundation

/// Which arena the room plays in.
enum GameMode: String, Codable, CaseIterable, Identifiable {
    case linear, circular
    var id: String { rawValue }

    var title: String {
        switch self {
        case .linear: return "Team Linear"
        case .circular: return "Circular"
        }
    }

    var subtitle: String {
        switch self {
        case .linear: return "Two teams, one rope. Pull the knot past your goal line."
        case .circular: return "Everyone is tied around a hole. Drag the others in. Last standing wins."
        }
    }
}

/// Circular mode can be played as two teams or free-for-all.
enum TeamMode: String, Codable, CaseIterable, Identifiable {
    case teams, individual
    var id: String { rawValue }

    var title: String {
        switch self {
        case .teams: return "Teams"
        case .individual: return "Free-for-all"
        }
    }
}

enum Team: String, Codable {
    case red, blue, none

    var title: String {
        switch self {
        case .red: return "Red"
        case .blue: return "Blue"
        case .none: return "Solo"
        }
    }

    var other: Team {
        switch self {
        case .red: return .blue
        case .blue: return .red
        case .none: return .none
        }
    }
}

enum RoomStatus: String, Codable {
    case lobby, countdown, playing, finished
}

/// `rooms/{code}/meta` – written by the host, read by everyone.
struct RoomMeta: Codable, Equatable {
    var code: String
    var mode: GameMode
    var teamMode: TeamMode
    var hostId: String
    var status: RoomStatus
    var createdAt: Double          // server time, ms
    var startAt: Double?           // server time (ms) when the current round goes live
    var winner: String?            // "red" | "blue" | player id | "draw"
    var round: Int
    var slotCount: Int             // participants in the current round (ring size in circular mode)
}

/// `rooms/{code}/players/{uid}` – one record per phone in the room.
struct PlayerRecord: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var photo: String?             // tiny base64 JPEG, optional
    var team: Team
    var slot: Int                  // -1 = not part of the current round (lobby / joined late)
    var colorIndex: Int            // palette index in free-for-all
    var joinedAt: Double           // server time, ms

    var initials: String { Self.initials(for: name) }

    static func initials(for name: String) -> String {
        let parts = name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0).uppercased() }
        if letters.isEmpty { return "?" }
        return letters.joined()
    }

    var isParticipating: Bool { slot >= 0 }
}

/// `rooms/{code}/inputs/{uid}` – each phone's live pulling input, read by the host.
struct PlayerInput: Codable, Equatable {
    var pull: Double               // 0...1 steady pull (tilt)
    var tugs: Int                  // number of tug bursts so far this round (monotonic)
    var t: Double                  // server time, ms

    static let zero = PlayerInput(pull: 0, tugs: 0, t: 0)
}

/// `rooms/{code}/state` – the host's simulation, published ~12x per second.
struct GameState: Codable, Equatable {
    var x: Double                  // linear: how far the knot has moved along the rope
    var vx: Double
    var holeR: Double              // circular: the hole in the middle, which grows all round
    var radii: [String: Double]    // circular: how far each player stands from the hole
    var radVel: [String: Double]   // circular: how fast they are sliding in or out
    var elim: [String: Double]     // player id -> elapsed seconds when they went out
    var seq: Int
    var elapsed: Double            // seconds since the round went live
    var t: Double                  // server time (ms) when published

    static func initial(holeR: Double = GameConfig.holeStartRadius) -> GameState {
        GameState(x: 0, vx: 0, holeR: holeR, radii: [:], radVel: [:], elim: [:], seq: 0, elapsed: 0, t: 0)
    }

    /// Where a player stands on the ledge; everyone starts halfway out.
    func radius(_ id: String) -> Double { radii[id] ?? GameConfig.startRadius }
}

enum RoomError: LocalizedError {
    case notFound(String)
    case offline(String)
    case full

    var errorDescription: String? {
        switch self {
        case .notFound(let code): return "No room with code \(code)."
        case .offline(let why): return why
        case .full: return "That room is full."
        }
    }
}

// Realtime Database drops empty maps, so the dictionaries may be missing on the wire.
extension GameState {
    enum CodingKeys: String, CodingKey { case x, vx, holeR, radii, radVel, elim, seq, elapsed, t }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        vx = try c.decodeIfPresent(Double.self, forKey: .vx) ?? 0
        holeR = try c.decodeIfPresent(Double.self, forKey: .holeR) ?? GameConfig.holeStartRadius
        radii = try c.decodeIfPresent([String: Double].self, forKey: .radii) ?? [:]
        radVel = try c.decodeIfPresent([String: Double].self, forKey: .radVel) ?? [:]
        elim = try c.decodeIfPresent([String: Double].self, forKey: .elim) ?? [:]
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        elapsed = try c.decodeIfPresent(Double.self, forKey: .elapsed) ?? 0
        t = try c.decodeIfPresent(Double.self, forKey: .t) ?? 0
    }
}
