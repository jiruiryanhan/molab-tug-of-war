import SwiftUI

struct GameView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var dragFired = 0

    private var frame: RenderFrame { session.frame }
    private var myColor: Color { Palette.color(team: frame.myTeam, colorIndex: frame.myColorIndex) }
    private var canTug: Bool { frame.status == .playing && frame.amParticipating && !frame.amEliminated }
    /// Landscape on an iPhone: keep the bars thin so the field gets the height.
    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            field
                .background {
                    // In the ring arena the pit runs to the edges, behind the bars.
                    (frame.mode == .circular ? Color.black : Color(.systemBackground))
                        .ignoresSafeArea()
                }
                .safeAreaInset(edge: .top, spacing: 0) { statusBar }
                .safeAreaInset(edge: .bottom, spacing: 0) { controlBar }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Leave") { app.leaveRoom() }
                    }
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 0) {
                            Text(session.isPractice ? "Practice" : session.code)
                                .font(.headline)
                                .monospaced(!session.isPractice)
                            Text(frame.mode == .circular
                                 ? "\(frame.mode.title) · \(frame.teamMode.title)"
                                 : frame.mode.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) { score }
                }
                .sheet(isPresented: Binding(get: { frame.status == .finished }, set: { _ in })) {
                    ResultsView(session: session)
                }
        }
        .onAppear { OrientationLock.set(OrientationLock.game) }
        .onDisappear { OrientationLock.set(OrientationLock.menus) }
    }

    // MARK: - Field

    private var field: some View {
        GeometryReader { geo in
            ZStack {
                GameCanvas(frame: frame, avatars: session.avatars)
                    .contentShape(Rectangle())
                    .onTapGesture { session.tug() }
                    .gesture(
                        DragGesture(minimumDistance: 10)
                            .onChanged { v in handleDrag(v) }
                            .onEnded { _ in dragFired = 0 }
                    )
                if let n = frame.countdownSeconds, frame.status == .countdown {
                    Text(n > 0 ? "\(n)" : "GO!")
                        .font(.system(size: compact ? 64 : 96, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: n)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityLabel(n > 0 ? "Starting in \(n)" : "Go")
                }
            }
            .onAppear { session.viewport = geo.size }
            .onChange(of: geo.size) { _, size in session.viewport = size }
        }
    }

    private func handleDrag(_ v: DragGesture.Value) {
        guard let dirW = frame.myPullDirectionWorld else { return }
        let d = frame.camera.toScreen(direction: dirW)
        let proj = Double(v.translation.width) * d.dx + Double(v.translation.height) * d.dy
        let fired = Int(floor(proj / 60))
        if fired > dragFired {
            for _ in 0..<(fired - dragFired) { session.tug() }
            dragFired = fired
        }
    }

    // MARK: - Bars

    @ViewBuilder
    private var score: some View {
        if frame.mode == .circular && frame.teamMode == .individual {
            Text("\(frame.aliveTotal) left")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                Text("\(frame.aliveRed)").foregroundStyle(Palette.red)
                Text("–").foregroundStyle(.secondary)
                Text("\(frame.aliveBlue)").foregroundStyle(Palette.blue)
            }
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .accessibilityLabel("Red \(frame.aliveRed), blue \(frame.aliveBlue)")
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        let message = statusMessage
        if frame.mode == .linear || message != nil {
            VStack(spacing: 4) {
                if frame.mode == .linear {
                    Gauge(value: clamp(frame.ropeX / GameConfig.goalDistance, -1, 1), in: -1...1) {
                        Text("Rope")
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("RED").font(.caption2).foregroundStyle(Palette.red)
                    } maximumValueLabel: {
                        Text("BLUE").font(.caption2).foregroundStyle(Palette.blue)
                    }
                    .gaugeStyle(.accessoryLinear)
                    .tint(Gradient(colors: [Palette.red, Palette.blue]))
                }
                if let message {
                    Label(message.text, systemImage: message.symbol)
                        .font(.caption)
                        .foregroundStyle(message.tint)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    private var statusMessage: (text: String, symbol: String, tint: Color)? {
        if !frame.isConnected {
            return ("Reconnecting…", "wifi.exclamationmark", .orange)
        }
        if frame.suddenDeath && frame.status == .playing {
            return ("Sudden death — the hole is growing fast", "exclamationmark.triangle.fill", .orange)
        }
        if !frame.amParticipating {
            return ("You are in the next round", "hourglass", .secondary)
        }
        if frame.amEliminated && frame.status == .playing {
            return ("You are out. Watching the rest.", "arrow.down.circle", .secondary)
        }
        if frame.waitingCount > 0 {
            return ("\(frame.waitingCount) waiting for the next round", "person.badge.clock", .secondary)
        }
        return nil
    }

    private var controlBar: some View {
        Group {
            if compact {
                HStack(spacing: 14) {
                    pullMeter.frame(maxWidth: 240)
                    tugButton
                    recenterButton
                }
            } else {
                VStack(spacing: 10) {
                    pullMeter
                    HStack(spacing: 12) {
                        tugButton
                        recenterButton
                    }
                    Text(session.motion.isAvailable
                         ? "Tilt toward the arrow to pull. Swipe or tap for a tug."
                         : "Swipe toward the arrow, tap the field, or press TUG!")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, compact ? 6 : 10)
        .padding(.bottom, compact ? 4 : 6)
        .background(.bar)
    }

    private var pullMeter: some View {
        HStack(spacing: 10) {
            Image(systemName: session.motion.isAvailable
                  ? "iphone.gen3.radiowaves.left.and.right" : "iphone.slash")
                .foregroundStyle(.secondary)
                .font(.caption)
            ProgressView(value: canTug ? frame.myPull : 0)
                .tint(myColor)
            Text(session.motion.isAvailable ? "\(Int(frame.myPull * 100))%" : "No tilt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pull strength")
    }

    private var tugButton: some View {
        Button {
            session.tug()
        } label: {
            Text("TUG!")
                .font(compact ? .title3.weight(.bold) : .title2.weight(.bold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(compact ? .large : .extraLarge)
        .tint(myColor)
        .disabled(!canTug)
    }

    private var recenterButton: some View {
        Button {
            session.recenterTilt()
        } label: {
            Image(systemName: "scope")
                .font(.title3)
        }
        .buttonStyle(.bordered)
        .controlSize(compact ? .large : .extraLarge)
        .disabled(!session.motion.isAvailable)
        .accessibilityLabel("Recenter tilt")
    }
}
