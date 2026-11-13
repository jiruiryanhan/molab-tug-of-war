import Foundation
import CoreGraphics

/// One player dot as the renderer needs it.
struct DotSprite: Identifiable {
    var id: String
    var slot: Int
    var position: CGPoint          // world space
    var team: Team
    var colorIndex: Int
    var initials: String
    var name: String
    var isMe: Bool
    var elimProgress: Double       // 0 = alive … 1 = gone (fall-in animation)
}

/// Snapshot of everything the game view draws, rebuilt every display frame.
struct RenderFrame {
    var mode: GameMode = .linear
    var teamMode: TeamMode = .teams
    var status: RoomStatus = .lobby
    var ropeX: Double = 0
    var knot: CGPoint = .zero         // circular: where the central knot is
    var ringRadius: Double = GameConfig.ringMinRadius
    var holeR: Double = GameConfig.holeRadius
    var dots: [DotSprite] = []
    var myId = ""
    var myTeam: Team = .none
    var myColorIndex = 0
    var amParticipating = false
    var amEliminated = false
    var myPullDirectionWorld: CGVector?
    var myPull: Double = 0
    var camera = CameraState()
    var countdownSeconds: Int?
    var elapsed: Double = 0
    var suddenDeath = false
    var aliveRed = 0
    var aliveBlue = 0
    var aliveTotal = 0
    var waitingCount = 0
    var winner: String?
    var tugPulse: Double = 0       // 1 right after a tug, fading to 0
}
