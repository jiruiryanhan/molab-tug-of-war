import Foundation
import CoreMotion
import CoreGraphics
import Observation

/// Turns the phone's tilt into a 0...1 pull toward a direction on screen.
///
/// `tilt.dx` is how far the right edge dips (radians, positive = right edge down) and
/// `tilt.dy` how far the top edge dips away from the player. "Tilt toward the arrow" is the
/// rule: the direction the game asks you to pull is the direction you tip the phone.
@MainActor
@Observable
final class MotionInput {
    private let manager = CMMotionManager()
    private(set) var isAvailable = false
    private(set) var tilt = CGVector.zero
    private var neutral = CGVector.zero
    private var wantsCalibration = true

    static let deadZone = 3.0 * .pi / 180
    static let fullPull = 22.0 * .pi / 180

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        isAvailable = true
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            // roll: right edge down (+), continuous through flat. pitch: top edge away (+),
            // 0 upright, 90° flat, continuous past both. Neither depends on how upright you hold it.
            let t = CGVector(dx: atan2(g.x, hypot(g.y, g.z)), dy: atan2(-g.z, -g.y))
            self.tilt = t
            if self.wantsCalibration {
                self.neutral = t
                self.wantsCalibration = false
            }
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Make the current holding angle the "no pull" position.
    func calibrate() { wantsCalibration = true }

    /// Pull strength toward `direction` (screen space, +x right, +y up).
    func pull(toward direction: CGVector) -> Double {
        guard isAvailable else { return 0 }
        let dx = tilt.dx - neutral.dx
        let dy = tilt.dy - neutral.dy
        let along = dx * direction.dx + dy * direction.dy
        let v = (along - Self.deadZone) / (Self.fullPull - Self.deadZone)
        return clamp(v, 0, 1)
    }
}
