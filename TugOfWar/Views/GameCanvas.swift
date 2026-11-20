import SwiftUI

/// Draws one `RenderFrame` through its camera. Pure drawing, no state.
/// Ink is `.primary` and the ledge is a system background colour, so the field reads in
/// light and dark mode; the pits are always black.
struct GameCanvas: View {
    let frame: RenderFrame
    let avatars: [String: UIImage]

    var body: some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let cam = frame.camera
            let z = cam.zoom
            let ink = Color.primary
            let paper = Color(.systemBackground)
            let ledge = Color(.secondarySystemBackground)
            func S(_ p: CGPoint) -> CGPoint { cam.toScreen(p, in: size) }
            func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            }

            switch frame.mode {
            case .linear:
                let center = S(.zero)
                // My team's half of the field.
                if frame.myTeam == .red {
                    ctx.fill(Path(CGRect(x: 0, y: 0, width: center.x, height: size.height)),
                             with: .color(Palette.red.opacity(0.12)))
                } else if frame.myTeam == .blue {
                    ctx.fill(Path(CGRect(x: center.x, y: 0, width: size.width - center.x, height: size.height)),
                             with: .color(Palette.blue.opacity(0.12)))
                }
                // Goal lines.
                for gx in [-GameConfig.goalDistance, GameConfig.goalDistance] {
                    let p = S(CGPoint(x: gx, y: 0))
                    var path = Path()
                    path.move(to: CGPoint(x: p.x, y: 0))
                    path.addLine(to: CGPoint(x: p.x, y: size.height))
                    ctx.stroke(path, with: .color((gx < 0 ? Palette.red : Palette.blue).opacity(0.6)),
                               style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    ctx.draw(Text(gx < 0 ? "RED GOAL" : "BLUE GOAL")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(gx < 0 ? Palette.red : Palette.blue),
                             at: CGPoint(x: p.x, y: size.height * 0.5 + 70 * z + 18))
                }
                // Centre line.
                var mid = Path()
                mid.move(to: CGPoint(x: center.x, y: 0))
                mid.addLine(to: CGPoint(x: center.x, y: size.height))
                ctx.stroke(mid, with: .color(ink.opacity(0.45)), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                // Rope.
                let xs = frame.dots.map { $0.position.x }
                let left = (xs.min() ?? -GameConfig.linearGap) - 30
                let right = (xs.max() ?? GameConfig.linearGap) + 30
                var rope = Path()
                rope.move(to: S(CGPoint(x: left, y: 0)))
                rope.addLine(to: S(CGPoint(x: right, y: 0)))
                ctx.stroke(rope, with: .color(ink), style: StrokeStyle(lineWidth: 8 * z, lineCap: .round))
                // Knot.
                let knot = S(CGPoint(x: frame.ropeX, y: 0))
                ctx.fill(circle(knot, 10 * z), with: .color(paper))
                ctx.stroke(circle(knot, 10 * z), with: .color(ink), lineWidth: 3 * z)

            case .circular:
                // A ring-shaped ledge: a pit outside it, and a growing hole inside it.
                let centre = S(.zero)
                let outerPx = frame.outerR * z
                let holePx = frame.holeR * z
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                var band = Path()
                band.addPath(circle(centre, outerPx))
                band.addPath(circle(centre, holePx))
                ctx.fill(band, with: .color(ledge), style: FillStyle(eoFill: true))
                ctx.stroke(circle(centre, outerPx), with: .color(ink.opacity(0.55)), lineWidth: 2.5)
                ctx.stroke(circle(centre, holePx), with: .color(ink.opacity(0.55)), lineWidth: 2.5)
                if frame.suddenDeath {
                    ctx.draw(Text("SUDDEN DEATH").font(.caption2.weight(.semibold))
                                .foregroundStyle(.white), at: centre)
                }
                // The shared rope, running through everyone still standing.
                let standing = frame.dots.filter { $0.elimProgress == 0 }.sorted { $0.slot < $1.slot }
                ctx.stroke(closedSpline(standing.map { S($0.position) }), with: .color(ink),
                           style: StrokeStyle(lineWidth: 8 * z, lineCap: .round, lineJoin: .round))
            }

            // Dots. A player who is out falls into whichever pit took them.
            for d in frame.dots {
                var p = S(d.position)
                var r = GameConfig.dotRadius * z
                var alpha = 1.0
                if d.elimProgress > 0 {
                    if d.elimProgress >= 1 { continue }
                    let radius = hypot(d.position.x, d.position.y)
                    let fellInward = frame.mode == .linear
                        || radius <= (frame.holeR + frame.outerR) / 2
                    let target = fellInward
                        ? S(.zero)
                        : S(CGPoint(x: d.position.x * 1.3, y: d.position.y * 1.3))
                    p = CGPoint(x: p.x + (target.x - p.x) * d.elimProgress,
                                y: p.y + (target.y - p.y) * d.elimProgress)
                    r *= 1 - 0.8 * d.elimProgress
                    alpha = 1 - d.elimProgress
                }
                let color = Palette.color(team: d.team, colorIndex: d.colorIndex)
                let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
                if d.isMe {
                    ctx.fill(circle(p, r + 8 * z), with: .color(color.opacity(0.25 * alpha)))
                }
                ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.3 * alpha)))
                if let img = avatars[d.id] {
                    var layer = ctx
                    layer.opacity = alpha
                    layer.clip(to: Path(ellipseIn: rect.insetBy(dx: 2 * z, dy: 2 * z)))
                    layer.draw(Image(uiImage: img), in: rect)
                } else {
                    ctx.draw(Text(d.initials)
                                .font(.system(size: r * 0.8, weight: .semibold, design: .rounded))
                                .foregroundStyle(ink.opacity(alpha)), at: p)
                }
                ctx.stroke(Path(ellipseIn: rect), with: .color(color.opacity(alpha)), lineWidth: 4 * z)
                if !d.isMe && z > 0.45 {
                    ctx.draw(Text(d.name).font(.caption2)
                                .foregroundStyle(Color.secondary.opacity(alpha)),
                             at: CGPoint(x: p.x, y: p.y + r + 11))
                }
            }

            // "TUG!" arrow next to my dot, pointing the way I pull.
            if let dirW = frame.myPullDirectionWorld,
               let me = frame.dots.first(where: { $0.isMe }), me.elimProgress == 0,
               frame.status == .playing || frame.status == .countdown {
                let d = cam.toScreen(direction: dirW)
                let p = S(me.position)
                let r = GameConfig.dotRadius * z
                let pulse = frame.tugPulse
                let lift = r + 46 + pulse * 6
                // Keep the arrow on screen: drop it below the dot when the dot is near the top.
                let anchor = CGPoint(x: p.x, y: p.y - lift < 40 ? p.y + lift : p.y - lift)
                let len = 40 + frame.myPull * 18 + pulse * 10
                let end = CGPoint(x: anchor.x + d.dx * len, y: anchor.y + d.dy * len)
                var arrow = Path()
                arrow.move(to: anchor)
                arrow.addLine(to: end)
                let hs = 11.0
                let perp = CGVector(dx: -d.dy, dy: d.dx)
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - d.dx * hs + perp.dx * hs * 0.7,
                                          y: end.y - d.dy * hs + perp.dy * hs * 0.7))
                arrow.move(to: end)
                arrow.addLine(to: CGPoint(x: end.x - d.dx * hs - perp.dx * hs * 0.7,
                                          y: end.y - d.dy * hs - perp.dy * hs * 0.7))
                ctx.stroke(arrow, with: .color(ink),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                let label = CGPoint(x: anchor.x - d.dx * 34, y: anchor.y - d.dy * 34)
                ctx.draw(Text("TUG!")
                            .font(.system(size: 21 + pulse * 5, weight: .bold, design: .rounded))
                            .foregroundStyle(ink), at: label)
            }
        }
    }

    /// Closed Catmull-Rom spline through the points (a line for two, nothing for fewer).
    private func closedSpline(_ pts: [CGPoint]) -> Path {
        var path = Path()
        let n = pts.count
        guard n >= 2 else { return path }
        if n == 2 {
            path.move(to: pts[0]); path.addLine(to: pts[1])
            return path
        }
        path.move(to: pts[0])
        for i in 0..<n {
            let p0 = pts[(i - 1 + n) % n], p1 = pts[i], p2 = pts[(i + 1) % n], p3 = pts[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}
