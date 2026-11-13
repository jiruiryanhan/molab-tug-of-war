import Foundation
import CoreGraphics

/// All tunable numbers in one place. Distances are in world points; forces in points/s².
enum GameConfig {
    static let dotRadius: Double = 24
    static let dotSpacing: Double = 72        // distance between neighbouring dots on the rope
    static let linearGap: Double = 90         // distance from the knot to the first dot on each side
    static let goalDistance: Double = 250     // linear: knot must travel this far to win
    static let ringMinRadius: Double = 170    // circular: rope ring radius (grows with many players)
    static let holeRadius: Double = 56        // circular: starting hole radius
    static let holeGrowDelay: Double = 20     // circular: seconds before sudden death starts
    static let holeGrowRate: Double = 6       // circular: hole radius growth, points per second

    static let pullForce: Double = 140        // acceleration per unit of steady (tilt) pull
    static let tugImpulse: Double = 55        // velocity added by one tug burst
    static let damping: Double = 1.8          // velocity decay per second (rope friction)
    static let ringSpring: Double = 1.0       // circular: elastic pull of the knot back to centre
    static let dragMargin: Double = 14        // circular: fall in when dragged to within this of the hole
    static let maxSpeed: Double = 420

    static let countdownMs: Double = 3500
    static let statePublishInterval: Double = 1.0 / 12.0
    static let inputSendInterval: Double = 0.1
    static let maxPlayers = 16
}

/// Where things sit in world space. Shared by the simulation and the renderer.
enum Layout {
    static func ringRadius(count: Int) -> Double {
        max(GameConfig.ringMinRadius, Double(count) * GameConfig.dotSpacing / (2 * .pi))
    }

    /// Slot 0 sits at the top of the ring; slots go clockwise on screen.
    static func ringAngle(slot: Int, count: Int) -> Double {
        -.pi / 2 + 2 * .pi * Double(slot) / Double(max(count, 1))
    }

    static func linearPosition(team: Team, slot: Int, ropeX: Double) -> CGPoint {
        let d = GameConfig.linearGap + Double(slot) * GameConfig.dotSpacing
        return CGPoint(x: ropeX + (team == .red ? -d : d), y: 0)
    }

    /// Circular: each player's rope runs from their base on the ring to the central knot and is
    /// taut at rest. When the knot moves away from a base, that player is dragged along the rope.
    static func circularPosition(slot: Int, count: Int, knot: CGPoint) -> CGPoint {
        let r = ringRadius(count: count)
        let u = outward(slot: slot, count: count)
        let base = CGPoint(x: r * u.dx, y: r * u.dy)
        let dx = knot.x - base.x, dy = knot.y - base.y
        let dist = hypot(dx, dy)
        let drag = dist - r
        guard drag > 0, dist > 0.001 else { return base }
        return CGPoint(x: base.x + dx / dist * drag, y: base.y + dy / dist * drag)
    }

    /// How far the knot has dragged a player off their base (0 while their rope is slack).
    static func circularDrag(slot: Int, count: Int, knot: CGPoint) -> Double {
        let r = ringRadius(count: count)
        let u = outward(slot: slot, count: count)
        return max(0, hypot(knot.x - r * u.dx, knot.y - r * u.dy) - r)
    }

    /// Dragged this far, a player loses their footing and falls into the hole.
    static func dragLimit(count: Int) -> Double {
        ringRadius(count: count) - GameConfig.holeRadius - GameConfig.dragMargin
    }

    /// Unit vector pointing away from the hole for a ring slot.
    static func outward(slot: Int, count: Int) -> CGVector {
        let a = ringAngle(slot: slot, count: count)
        return CGVector(dx: cos(a), dy: sin(a))
    }
}

func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
