import SwiftUI

struct GameView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app
    @State private var dragFired = 0

    var body: some View {
        GeometryReader { geo in
            let frame = session.frame
            let myColor = Palette.color(team: frame.myTeam, colorIndex: frame.myColorIndex)
            ZStack {
                Palette.paper.ignoresSafeArea()

                GameCanvas(frame: frame, avatars: session.avatars)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { session.tug() }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in handleDrag(v, frame: frame) }
                            .onEnded { _ in dragFired = 0 }
                    )

                VStack(spacing: 0) {
                    topBar(frame)
                    Spacer()
                    bottomBar(frame, color: myColor)
                }

                if let n = frame.countdownSeconds, frame.status == .countdown {
                    Text(n > 0 ? "\(n)" : "GO!")
                        .font(.system(size: 110, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.85))
                        .contentTransition(.numericText())
                        .animation(.snappy, value: n)
                }

                if frame.status == .finished {
                    ResultsOverlay(session: session)
                }
            }
            .onAppear { session.viewport = geo.size }
            .onChange(of: geo.size) { _, s in session.viewport = s }
        }
        .statusBarHidden(false)
    }

    private func handleDrag(_ v: DragGesture.Value, frame: RenderFrame) {
        guard let dirW = frame.myPullDirectionWorld else { return }
        let d = frame.camera.toScreen(direction: dirW)
        let proj = Double(v.translation.width) * d.dx + Double(v.translation.height) * d.dy
        let fired = Int(floor(proj / 60))
        if fired > dragFired {
            for _ in 0..<(fired - dragFired) { session.tug() }
            dragFired = fired
        }
    }

    // MARK: HUD

    @ViewBuilder
    private func topBar(_ frame: RenderFrame) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button(role: .destructive) { app.leaveRoom() } label: {
                    Image(systemName: "xmark").font(.headline).padding(8)
                }
                .buttonStyle(.bordered)
                Spacer()
                VStack(spacing: 2) {
                    Text(session.isPractice ? "PRACTICE" : session.code)
                        .font(.system(.subheadline, design: .monospaced).bold())
                    Text(frame.mode.title + (frame.mode == .circular ? " · " + frame.teamMode.title : ""))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                switch frame.mode {
                case .linear:
                    HStack(spacing: 6) {
                        Text("\(frame.aliveRed)").foregroundStyle(Palette.red)
                        Text("v").foregroundStyle(.secondary)
                        Text("\(frame.aliveBlue)").foregroundStyle(Palette.blue)
                    }
                    .font(.headline.monospacedDigit())
                case .circular:
                    if frame.teamMode == .teams {
                        HStack(spacing: 6) {
                            Text("\(frame.aliveRed)").foregroundStyle(Palette.red)
                            Text("v").foregroundStyle(.secondary)
                            Text("\(frame.aliveBlue)").foregroundStyle(Palette.blue)
                        }
                        .font(.headline.monospacedDigit())
                    } else {
                        Text("\(frame.aliveTotal) left").font(.headline.monospacedDigit())
                    }
                }
            }
            if frame.mode == .linear {
                TugMeter(x: frame.ropeX / GameConfig.goalDistance)
            } else if frame.suddenDeath {
                Text("Sudden death — the hole is growing")
                    .font(.caption.bold()).foregroundStyle(.red)
            }
            if !frame.isConnected {
                Label("Reconnecting…", systemImage: "wifi.exclamationmark")
                    .font(.caption.bold()).padding(6)
                    .background(.orange.opacity(0.2), in: Capsule())
            }
            if !frame.amParticipating {
                Text("You joined mid-round. You're in the next one.")
                    .font(.caption).padding(6)
                    .background(.thinMaterial, in: Capsule())
            } else if frame.amEliminated && frame.status == .playing {
                Text("You fell in! Watching the rest…")
                    .font(.caption.bold()).padding(6)
                    .background(.thinMaterial, in: Capsule())
            } else if frame.waitingCount > 0 {
                Text("\(frame.waitingCount) waiting for the next round")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func bottomBar(_ frame: RenderFrame, color: Color) -> some View {
        let canTug = frame.status == .playing && frame.amParticipating && !frame.amEliminated
        VStack(spacing: 10) {
            if canTug {
                PullMeter(value: frame.myPull, color: color, tiltAvailable: session.motion.isAvailable)
            }
            HStack(spacing: 12) {
                Button {
                    session.tug()
                } label: {
                    Text("TUG!")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(color)
                .disabled(!canTug)
                Button {
                    session.recenterTilt()
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "scope").font(.title2)
                        Text("recenter").font(.caption2)
                    }
                    .frame(width: 64, height: 72)
                }
                .buttonStyle(.bordered)
                .disabled(!session.motion.isAvailable)
            }
            Text(session.motion.isAvailable
                 ? "Tilt toward the arrow to pull · swipe or tap for a TUG"
                 : "Swipe toward the arrow, tap the field, or press TUG!")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [Palette.paper.opacity(0), Palette.paper.opacity(0.92), Palette.paper],
                           startPoint: .top, endPoint: .bottom)
                .padding(.top, -30)
        )
    }
}

/// Linear mode: where the knot sits between the two goal lines.
struct TugMeter: View {
    var x: Double   // -1 (red goal) … +1 (blue goal)

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let pos = w * (0.5 + clamp(x, -1, 1) / 2)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(Palette.red.opacity(0.35))
                    Rectangle().fill(Palette.blue.opacity(0.35))
                }
                .clipShape(Capsule())
                Rectangle().fill(.black.opacity(0.5)).frame(width: 1).offset(x: w / 2)
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.black, lineWidth: 2))
                    .frame(width: 16, height: 16)
                    .offset(x: pos - 8)
            }
        }
        .frame(height: 16)
    }
}

/// My current steady pull from the tilt.
struct PullMeter: View {
    var value: Double
    var color: Color
    var tiltAvailable: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tiltAvailable ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.08))
                    Capsule().fill(color).frame(width: max(0, g.size.width * value))
                }
            }
            .frame(height: 8)
            Text(tiltAvailable ? "\(Int(value * 100))%" : "no tilt")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }
}
