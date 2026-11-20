import SwiftUI

struct GameView: View {
    let session: RoomSession
    @Environment(AppModel.self) private var app
    @State private var dragFired = 0

    private var frame: RenderFrame { session.frame }
    private var myColor: Color { Palette.color(team: frame.myTeam, colorIndex: frame.myColorIndex) }
    private var canTug: Bool { frame.status == .playing && frame.amParticipating && !frame.amEliminated }

    var body: some View {
        NavigationStack {
            field
                .background(Color(.systemBackground))
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
                        .font(.system(size: 96, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: n)
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
        VStack(spacing: 6) {
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
            if let message = statusMessage {
                Label(message.text, systemImage: message.symbol)
                    .font(.caption)
                    .foregroundStyle(message.tint)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var statusMessage: (text: String, symbol: String, tint: Color)? {
        if !frame.isConnected {
            return ("Reconnecting…", "wifi.exclamationmark", .orange)
        }
        if frame.suddenDeath && frame.status == .playing {
            return ("Sudden death — the hole is growing", "exclamationmark.triangle.fill", .orange)
        }
        if !frame.amParticipating {
            return ("You are in the next round", "hourglass", .secondary)
        }
        if frame.amEliminated && frame.status == .playing {
            return ("You fell in. Watching the rest.", "arrow.down.circle", .secondary)
        }
        if frame.waitingCount > 0 {
            return ("\(frame.waitingCount) waiting for the next round", "person.badge.clock", .secondary)
        }
        return nil
    }

    private var controlBar: some View {
        VStack(spacing: 10) {
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

            HStack(spacing: 12) {
                Button {
                    session.tug()
                } label: {
                    Text("TUG!")
                        .font(.title2.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .tint(myColor)
                .disabled(!canTug)

                Button {
                    session.recenterTilt()
                } label: {
                    Image(systemName: "scope")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
                .controlSize(.extraLarge)
                .disabled(!session.motion.isAvailable)
                .accessibilityLabel("Recenter tilt")
            }

            Text(session.motion.isAvailable
                 ? "Tilt toward the arrow to pull. Swipe or tap for a tug."
                 : "Swipe toward the arrow, tap the field, or press TUG!")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
