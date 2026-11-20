import Foundation
import CoreMotion
import CoreGraphics
import UIKit
import Observation

/// Turns the phone's tilt into a 0...1 pull toward a direction on screen.
///
/// `tilt.dx` is how far the right edge dips (radians, positive = right edge down) and
/// `tilt.dy` how far the top edge dips away from the player, both in device axes. The game
/// is played in landscape, so the tilt is rotated into screen axes before it is used:
/// "tilt toward the arrow" holds however the phone is turned.
@MainActor
@Observable
final class MotionInput {
    private let manager = CMMotionManager()
    private(set) var isAvailable = false
    private(set) var tilt = CGVector.zero          // device axes
    private var neutral = CGVector.zero
    private var wantsCalibration = true
    private var orientation: UIInterfaceOrientation = .portrait

    static let deadZone = 3.0 * .pi / 180
    static let fullPull = 22.0 * .pi / 180

    func start() {
        refreshOrientation()
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
            self.refreshOrientation()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// Make the current holding angle the "no pull" position.
    func calibrate() {
        refreshOrientation()
        wantsCalibration = true
    }

    private func refreshOrientation() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        orientation = scene.interfaceOrientation
    }

    /// The tilt in screen axes: +x toward the right of the screen, +y toward the top.
    private var screenTilt: CGVector {
        let dx = tilt.dx - neutral.dx
        let dy = tilt.dy - neutral.dy
        switch orientation {
        case .landscapeLeft:            // device's top edge points to the left of the screen
            return CGVector(dx: -dy, dy: dx)
        case .landscapeRight:
            return CGVector(dx: dy, dy: -dx)
        case .portraitUpsideDown:
            return CGVector(dx: -dx, dy: -dy)
        default:
            return CGVector(dx: dx, dy: dy)
        }
    }

    /// Pull strength toward `direction` (screen space, +x right, +y up).
    func pull(toward direction: CGVector) -> Double {
        guard isAvailable else { return 0 }
        let t = screenTilt
        let along = t.dx * direction.dx + t.dy * direction.dy
        let v = (along - Self.deadZone) / (Self.fullPull - Self.deadZone)
        return clamp(v, 0, 1)
    }
}
