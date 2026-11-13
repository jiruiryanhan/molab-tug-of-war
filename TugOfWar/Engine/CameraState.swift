import Foundation
import CoreGraphics

/// The view's window into world space: a centre point, a zoom and a rotation.
struct CameraState: Equatable {
    var center: CGPoint = .zero
    var zoom: Double = 1
    var rotation: Double = 0         // radians, applied after translation+zoom
    var initialized = false

    /// Move smoothly toward a target (exponential approach, frame-rate independent).
    mutating func approach(_ target: CameraState, dt: Double) {
        guard initialized else {
            self = target
            initialized = true
            return
        }
        let kc = 1 - exp(-dt * 5.0)
        let kz = 1 - exp(-dt * 4.0)
        let kr = 1 - exp(-dt * 6.0)
        center.x += (target.center.x - center.x) * kc
        center.y += (target.center.y - center.y) * kc
        zoom += (target.zoom - zoom) * kz
        var dr = target.rotation - rotation
        while dr > .pi { dr -= 2 * .pi }
        while dr < -.pi { dr += 2 * .pi }
        rotation += dr * kr
    }

    /// World point -> screen point (screen y grows downward, like world y).
    func toScreen(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let dx = (p.x - center.x) * zoom
        let dy = (p.y - center.y) * zoom
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: size.width / 2 + dx * c - dy * s,
                       y: size.height / 2 + dx * s + dy * c)
    }

    /// World direction -> screen direction (rotation only).
    func toScreen(direction v: CGVector) -> CGVector {
        let c = cos(rotation), s = sin(rotation)
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }
}
