import UIKit

/// A CADisplayLink wrapper that calls back on the main actor with the frame's dt.
@MainActor
final class DisplayTicker: NSObject {
    var handler: (@MainActor (Double) -> Void)?
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ l: CADisplayLink) {
        let dt = last == 0 ? 1.0 / 60.0 : l.timestamp - last
        last = l.timestamp
        handler?(clamp(dt, 0, 0.05))
    }
}
