import Foundation
import CoreGraphics

/// All tunable numbers in one place. Distances are in world points; forces in points/s².
enum GameConfig {
    static let dotRadius: Double = 30
    static let dotSpacing: Double = 84        // distance between neighbouring dots on the rope
    static let linearGap: Double = 100         // distance from the knot to the first dot on each side
    static let goalDistance: Double = 250     // linear: knot must travel this far to win

    // Linear: steady pull and tug bursts move the knot along the rope.
    static let pullForce: Double = 140        // acceleration per unit of steady (tilt) pull
    static let tugImpulse: Double = 55        // velocity added by one tug burst
    static let damping: Double = 1.8          // velocity decay per second (rope friction)
    static let maxSpeed: Double = 420

    // Circular: a ring-shaped ledge with a growing hole inside it and a pit outside it.
    // Everyone holds one rope, so the ground you win is ground somebody else loses.
    static let holeStartRadius: Double = 110  // the hole at the start of a round
    static let outerRadius: Double = 430      // past this you drop off the outer edge
    static let startRadius: Double = 270      // where players stand when the round begins
    static let holeGrowDelay: Double = 5      // seconds of grace before the hole starts growing
    static let holeGrowRate: Double = 5       // points per second
    static let holeRushDelay: Double = 30     // after this the hole grows much faster
    static let holeRushRate: Double = 20
    static let radialForce: Double = 190      // acceleration per unit of pull above the average
    static let radialTug: Double = 32         // velocity from one tug burst above the average
    static let radialDamping: Double = 2.2    // you slide for a moment, then settle
    static let maxRadialSpeed: Double = 220

    static let countdownMs: Double = 3500
    static let statePublishInterval: Double = 1.0 / 12.0
    static let inputSendInterval: Double = 0.1
    static let maxPlayers = 16

    /// Middle of the ledge, used for framing and for how hard the bots pull.
    static func bandMiddle(hole: Double) -> Double { (hole + outerRadius) / 2 }
}

/// Where things sit in world space. Shared by the simulation and the renderer.
enum Layout {
    /// Slot 0 sits at the top of the ring; slots go clockwise on screen.
    static func ringAngle(slot: Int, count: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(slot) / Double(max(count, 1))
    }

    static func linearPosition(team: Team, slot: Int, ropeX: Double) -> CGPoint {
        let d = GameConfig.linearGap + Double(slot) * GameConfig.dotSpacing
        return CGPoint(x: ropeX + (team == .red ? -d : d), y: 0)
    }

    /// Circular: a player keeps their angle around the ring and only moves in or out.
    static func circularPosition(slot: Int, count: Int, radius: Double) -> CGPoint {
        let a = ringAngle(slot: slot, count: count)
        return CGPoint(x: radius * cos(a), y: radius * sin(a))
    }

    /// Unit vector pointing away from the hole for a ring slot.
    static func outward(slot: Int, count: Int) -> CGVector {
        let a = ringAngle(slot: slot, count: count)
        return CGVector(dx: cos(a), dy: sin(a))
    }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
