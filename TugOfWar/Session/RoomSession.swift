import SwiftUI
import UIKit
import Observation

/// Everything about one room: lobby membership, the host's simulation, every client's
/// interpolation and camera, and the per-frame snapshot the game view draws.
///
/// Data flow (mirrors the class MoLobby pattern of `observe(.value)` listeners):
///   meta     host -> all        room status, mode, host id, round, winner
///   players  everyone -> all    name, photo, team, slot
///   inputs   everyone -> host   pull + tug count, ≤10 writes/s per phone while playing
///   state    host -> all        knot / ring position, eliminations, ~12 writes/s
@MainActor
@Observable
final class RoomSession {
    let code: String
    let transport: RoomTransport
    let isPractice: Bool
    let motion = MotionInput()

    private(set) var meta: RoomMeta?
    private(set) var players: [PlayerRecord] = []
    private(set) var display = GameState.initial()
    private(set) var camera = CameraState()
    private(set) var frame = RenderFrame()
    private(set) var avatars: [String: UIImage] = [:]
    var viewport = CGSize(width: 390, height: 780)
    var errorMessage: String?
    /// DEBUG: pulls and tugs by itself, so the simulator can play a round with no touch input.
    var debugAutoTug = false
    private(set) var closed = false

    @ObservationIgnored private var inputs: [String: PlayerInput] = [:]
    @ObservationIgnored private var netState: GameState?
    @ObservationIgnored private var engine: GameEngine?
    @ObservationIgnored private var myInput = PlayerInput.zero
    @ObservationIgnored private var lastSentInput: PlayerInput?
    @ObservationIgnored private var lastInputSend: TimeInterval = 0
    @ObservationIgnored private var lastPublish: TimeInterval = 0
    @ObservationIgnored private var publishSeq = 0
    @ObservationIgnored private var netReceivedAt: TimeInterval = 0
    @ObservationIgnored private var tokens: [ObserverToken] = []
    @ObservationIgnored private var ticker: DisplayTicker?
    @ObservationIgnored private var bots: BotController?
    @ObservationIgnored private var elimSeen: [String: TimeInterval] = [:]
    @ObservationIgnored private var lastRound = -1
    @ObservationIgnored private var hasSeenMeta = false
    @ObservationIgnored private var joined = false
    @ObservationIgnored private var myRecord: PlayerRecord?
    @ObservationIgnored private var myRecordRound = -1
    @ObservationIgnored private var hostClaimPending = false
    @ObservationIgnored private var lastTugAt: TimeInterval = -10
    @ObservationIgnored private var avatarKeys: [String: String] = [:]
    @ObservationIgnored private var profile: Profile

    init(code: String, transport: RoomTransport, profile: Profile, isPractice: Bool) {
        self.code = code
        self.transport = transport
        self.profile = profile
        self.isPractice = isPractice
    }

    // MARK: - Derived

    var myId: String { transport.myId }
    var isHost: Bool { meta?.hostId == myId }
    var me: PlayerRecord? { players.first { $0.id == myId } }
    var status: RoomStatus { meta?.status ?? .lobby }
    var mode: GameMode { meta?.mode ?? .linear }
    var serverNow: Double { transport.serverNow }
    var amParticipating: Bool { (me?.slot ?? -1) >= 0 }
    var amEliminated: Bool { display.elim[myId] != nil }
    var canStart: Bool { isHost && players.count >= 2 && (status == .lobby || status == .finished) }

    func player(_ id: String) -> PlayerRecord? { players.first { $0.id == id } }

    // MARK: - Lifecycle

    func create(mode: GameMode, teamMode: TeamMode) async {
        let meta = RoomMeta(code: code, mode: mode, teamMode: mode == .linear ? .teams : teamMode,
                            hostId: myId, status: .lobby, createdAt: serverNow, startAt: nil,
                            winner: nil, round: 0, slotCount: 0)
        transport.set(RoomPaths.room(code), value: [
            "meta": RTCodec.encode(meta),
            "state": RTCodec.encode(GameState.initial()),
        ])
        transport.onDisconnectSet(RoomPaths.meta(code) + "/hostId", value: "")
        await join(existing: meta)
    }

    func join() async throws {
        guard let any = await transport.read(RoomPaths.meta(code)),
              let meta: RoomMeta = RTCodec.decode(any) else {
            throw RoomError.notFound(code)
        }
        await join(existing: meta)
    }

    private func join(existing meta: RoomMeta) async {
        var team = Team.none
        if meta.mode == .linear {
            let current = (await transport.read(RoomPaths.players(code)) as? [String: Any]) ?? [:]
            let recs: [PlayerRecord] = current.values.compactMap { RTCodec.decode($0) }
            let reds = recs.filter { $0.team == .red }.count
            let blues = recs.filter { $0.team == .blue }.count
            team = reds < blues ? .red : (blues < reds ? .blue : (Bool.random() ? .red : .blue))
        }
        let rec = PlayerRecord(id: myId, name: profile.name, photo: profile.photo, team: team,
                               slot: -1, colorIndex: team == .blue ? 1 : 0, joinedAt: serverNow)
        myRecord = rec
        transport.set(RoomPaths.player(code, myId), value: RTCodec.encode(rec))
        transport.onDisconnectRemove(RoomPaths.player(code, myId))
        transport.onDisconnectRemove(RoomPaths.input(code, myId))
        joined = true
        self.meta = meta
        beginObserving()
    }

    func addBots(count: Int) {
        let b = BotController(transport: transport, code: code)
        b.join(count: count, mode: mode, myTeam: me?.team ?? myRecord?.team ?? .red)
        // So a bot on the ring can ease off near the outer edge and dig in near the hole.
        b.radiusProvider = { [weak self] id in self?.display.radii[id] }
        b.holeProvider = { [weak self] in self?.display.holeR ?? GameConfig.holeStartRadius }
        bots = b
    }

    private func beginObserving() {
        tokens.append(transport.observe(RoomPaths.meta(code)) { [weak self] v in self?.handleMeta(v) })
        tokens.append(transport.observe(RoomPaths.players(code)) { [weak self] v in self?.handlePlayers(v) })
        tokens.append(transport.observe(RoomPaths.state(code)) { [weak self] v in self?.handleState(v) })
        tokens.append(transport.observe(RoomPaths.inputs(code)) { [weak self] v in self?.handleInputs(v) })
        let t = DisplayTicker()
        t.handler = { [weak self] dt in self?.tick(dt: dt) }
        t.start()
        ticker = t
        motion.start()
    }

    private func stop() {
        ticker?.stop()
        ticker = nil
        motion.stop()
        for t in tokens { transport.removeObserver(t) }
        tokens = []
        bots?.stop()
    }

    func leave() {
        stop()
        let metaPath = RoomPaths.meta(code)
        if isHost {
            if let next = players.first(where: { $0.id != myId && !$0.id.hasPrefix("bot-") }) {
                transport.update([
                    metaPath + "/hostId": next.id,
                    RoomPaths.player(code, myId): NSNull(),
                    RoomPaths.input(code, myId): NSNull(),
                ])
            } else {
                transport.set(RoomPaths.room(code), value: nil)
            }
            transport.cancelDisconnectOperations(metaPath + "/hostId")
        } else {
            transport.set(RoomPaths.player(code, myId), value: nil)
            transport.set(RoomPaths.input(code, myId), value: nil)
        }
        transport.cancelDisconnectOperations(RoomPaths.player(code, myId))
        transport.cancelDisconnectOperations(RoomPaths.input(code, myId))
        joined = false
    }

    // MARK: - Incoming data

    private func handleMeta(_ v: Any?) {
        guard let m: RoomMeta = RTCodec.decode(v) else {
            if hasSeenMeta && !closed {
                closed = true
                errorMessage = "The room was closed."
                stop()
            }
            return
        }
        hasSeenMeta = true
        let previous = meta
        meta = m

        if m.round != lastRound {
            lastRound = m.round
            resetRoundLocal()
            if isHost && (m.status == .countdown || m.status == .playing) {
                engine = GameEngine(mode: m.mode, teamMode: m.teamMode, slotCount: m.slotCount, state: .initial())
            }
        } else if isHost, engine == nil, m.status == .countdown || m.status == .playing {
            // Became host mid-round (previous host left): continue from the last published state.
            engine = GameEngine(mode: m.mode, teamMode: m.teamMode, slotCount: m.slotCount,
                                state: netState ?? .initial())
        }
        if !isHost || m.status == .lobby || m.status == .finished { engine = nil }

        if m.status != previous?.status {
            if m.status == .countdown {
                motion.calibrate()
                myInput = .zero
                lastSentInput = nil
            }
            if m.status == .lobby {
                display = .initial()
                netState = nil
                elimSeen = [:]
            }
        }
        checkHost()
    }

    private func resetRoundLocal() {
        engine = nil
        myInput = .zero
        lastSentInput = nil
        elimSeen = [:]
        display = .initial()
        netState = nil
        lastTugAt = -10
    }

    private func handlePlayers(_ v: Any?) {
        let dict = v as? [String: Any] ?? [:]
        let recs: [PlayerRecord] = dict.values.compactMap { RTCodec.decode($0) }
        players = recs.sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }

        if let mine = players.first(where: { $0.id == myId }) {
            myRecord = mine
            myRecordRound = meta?.round ?? -1
        } else if joined, !closed, let meta, var rec = myRecord {
            // We were dropped (reconnect after a disconnect): put ourselves back. Our old seat
            // is only valid while the round we were seated in is still running.
            if myRecordRound != meta.round || meta.status == .lobby { rec.slot = -1 }
            myRecord = rec
            transport.set(RoomPaths.player(code, myId), value: RTCodec.encode(rec))
            transport.onDisconnectRemove(RoomPaths.player(code, myId))
            transport.onDisconnectRemove(RoomPaths.input(code, myId))
            lastSentInput = nil   // inputs/{uid} was removed too; republish on the next tick
        }

        for p in players {
            if let photo = p.photo {
                if avatarKeys[p.id] != photo {
                    avatarKeys[p.id] = photo
                    avatars[p.id] = Profile.decode(photo)
                }
            } else if avatars[p.id] != nil {
                avatars[p.id] = nil
                avatarKeys[p.id] = nil
            }
        }
        checkHost()
    }

    private func handleState(_ v: Any?) {
        guard let s: GameState = RTCodec.decode(v) else { return }
        netState = s
        netReceivedAt = CACurrentMediaTime()
        if !isHost && s.seq == 0 { display = s }     // fresh round: snap, don't glide
    }

    private func handleInputs(_ v: Any?) {
        let dict = v as? [String: Any] ?? [:]
        var map: [String: PlayerInput] = [:]
        for (k, val) in dict {
            if let i: PlayerInput = RTCodec.decode(val) { map[k] = i }
        }
        inputs = map
    }

    /// If the host vanished, the longest-present player takes over (atomic compare-and-set).
    private func checkHost() {
        guard let meta, !players.isEmpty, !hostClaimPending, !closed else { return }
        let hostPresent = players.contains { $0.id == meta.hostId }
        guard !hostPresent, players.first(where: { !$0.id.hasPrefix("bot-") })?.id == myId else { return }
        hostClaimPending = true
        let oldHost = meta.hostId
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self else { return }
            defer { self.hostClaimPending = false }
            guard let m = self.meta, !self.players.contains(where: { $0.id == m.hostId }) else { return }
            let path = RoomPaths.meta(self.code) + "/hostId"
            let ok = await self.transport.compareAndSet(path, expected: { cur in
                let c = cur as? String ?? ""
                return c.isEmpty || c == oldHost
            }, value: self.myId)
            if ok { self.transport.onDisconnectSet(path, value: "") }
        }
    }

    // MARK: - Lobby actions

    func switchTeam() {
        guard let me, mode == .linear, status == .lobby || status == .finished else { return }
        let t = me.team == .red ? Team.blue : Team.red
        transport.update([
            RoomPaths.player(code, myId) + "/team": t.rawValue,
            RoomPaths.player(code, myId) + "/colorIndex": t == .blue ? 1 : 0,
        ])
    }

    func shuffleTeams() {
        guard isHost, mode == .linear else { return }
        var u: [String: Any] = [:]
        for (i, p) in players.shuffled().enumerated() {
            let t: Team = i % 2 == 0 ? .red : .blue
            u[RoomPaths.player(code, p.id) + "/team"] = t.rawValue
            u[RoomPaths.player(code, p.id) + "/colorIndex"] = t == .blue ? 1 : 0
        }
        transport.update(u)
    }

    /// Host only: seat everyone, zero the inputs, and start the countdown.
    func startRound() {
        guard let meta, canStart else { return }
        let parts = Array(players.prefix(GameConfig.maxPlayers))
        var u: [String: Any] = [:]
        func seat(_ p: PlayerRecord, team: Team, slot: Int, color: Int) {
            let base = RoomPaths.player(code, p.id)
            u[base + "/team"] = team.rawValue
            u[base + "/slot"] = slot
            u[base + "/colorIndex"] = color
        }

        switch meta.mode {
        case .linear:
            var reds = parts.filter { $0.team == .red }
            var blues = parts.filter { $0.team == .blue }
            for p in parts where p.team == .none {
                if reds.count <= blues.count { reds.append(p) } else { blues.append(p) }
            }
            if reds.isEmpty || blues.isEmpty {
                reds = []; blues = []
                for (i, p) in parts.shuffled().enumerated() {
                    if i % 2 == 0 { reds.append(p) } else { blues.append(p) }
                }
            }
            for (i, p) in reds.enumerated() { seat(p, team: .red, slot: i, color: 0) }
            for (i, p) in blues.enumerated() { seat(p, team: .blue, slot: i, color: 1) }
        case .circular:
            let order = parts.shuffled()
            if meta.teamMode == .teams {
                // Balanced random teams, then random seats around the ring.
                let teamed = order.enumerated().map { ($0.element, $0.offset % 2 == 0 ? Team.red : Team.blue) }
                for (slot, pair) in teamed.shuffled().enumerated() {
                    seat(pair.0, team: pair.1, slot: slot, color: pair.1 == .blue ? 1 : 0)
                }
            } else {
                for (slot, p) in order.enumerated() { seat(p, team: .none, slot: slot, color: slot) }
            }
        }
        for p in players where !parts.contains(where: { $0.id == p.id }) {
            u[RoomPaths.player(code, p.id) + "/slot"] = -1
        }
        for p in parts {
            u[RoomPaths.input(code, p.id)] = RTCodec.encode(PlayerInput(pull: 0, tugs: 0, t: serverNow))
        }
        let m = RoomPaths.meta(code)
        u[m + "/status"] = RoomStatus.countdown.rawValue
        u[m + "/startAt"] = serverNow + GameConfig.countdownMs
        u[m + "/round"] = meta.round + 1
        u[m + "/winner"] = NSNull()
        u[m + "/slotCount"] = parts.count
        u[RoomPaths.state(code)] = RTCodec.encode(GameState.initial())
        transport.update(u)
    }

    func backToLobby() {
        guard isHost else { return }
        var u: [String: Any] = [:]
        let m = RoomPaths.meta(code)
        u[m + "/status"] = RoomStatus.lobby.rawValue
        u[m + "/winner"] = NSNull()
        u[m + "/startAt"] = NSNull()
        u[RoomPaths.state(code)] = RTCodec.encode(GameState.initial())
        for p in players { u[RoomPaths.player(code, p.id) + "/slot"] = -1 }
        transport.update(u)
    }

    private func finishRound(_ outcome: RoundOutcome, finalState: GameState) {
        var u: [String: Any] = [:]
        let m = RoomPaths.meta(code)
        u[m + "/status"] = RoomStatus.finished.rawValue
        switch outcome {
        case .winner(let w): u[m + "/winner"] = w
        case .draw: u[m + "/winner"] = "draw"
        }
        publishSeq += 1
        var s = finalState
        s.seq = publishSeq
        s.t = serverNow
        u[RoomPaths.state(code)] = RTCodec.encode(s)
        transport.update(u)
        display = s
        engine = nil
    }

    // MARK: - Input

    func tug() {
        guard status == .playing, amParticipating, !amEliminated else { return }
        myInput.tugs += 1
        lastTugAt = CACurrentMediaTime()
    }

    func recenterTilt() { motion.calibrate() }

    func updateProfile(_ p: Profile) { profile = p }

    /// Which way my dot pulls, in world space.
    func pullDirectionWorld() -> CGVector? {
        guard let me, me.slot >= 0, let meta else { return nil }
        switch meta.mode {
        case .linear:
            switch me.team {
            case .red: return CGVector(dx: -1, dy: 0)
            case .blue: return CGVector(dx: 1, dy: 0)
            case .none: return nil
            }
        case .circular:
            return Layout.outward(slot: me.slot, count: meta.slotCount)
        }
    }

    // MARK: - Per-frame

    private func tick(dt: Double) {
        guard let meta, !closed else { return }
        let now = CACurrentMediaTime()

        // 1. Steady pull from the phone's tilt, toward the on-screen arrow.
        if status == .playing, let dirW = pullDirectionWorld(), !amEliminated {
            let dirS = camera.toScreen(direction: dirW)
            var dirUp = CGVector(dx: dirS.dx, dy: -dirS.dy)
            if profile.invertTilt { dirUp = CGVector(dx: -dirUp.dx, dy: -dirUp.dy) }
            myInput.pull = motion.pull(toward: dirUp)
        } else {
            myInput.pull = 0
        }
        #if DEBUG
        if debugAutoTug, status == .playing, amParticipating, !amEliminated {
            myInput.pull = 0.5 + 0.4 * sin(now * 0.7)
            if now - lastTugAt > 0.8 { tug() }
        }
        #endif

        // 2. Send my input, throttled and only when it changed.
        if status == .playing, amParticipating, !amEliminated,
           now - lastInputSend >= GameConfig.inputSendInterval {
            let changed = lastSentInput.map { abs($0.pull - myInput.pull) > 0.03 || $0.tugs != myInput.tugs } ?? true
            if changed {
                myInput.t = serverNow
                transport.set(RoomPaths.input(code, myId), value: RTCodec.encode(myInput))
                lastSentInput = myInput
                lastInputSend = now
            }
        }

        // 3. Host: advance the simulation and publish. Client: glide toward the host's state.
        //    A host whose socket is down pauses rather than piling up writes to replay later.
        if isHost && transport.isConnected {
            if status == .countdown, let startAt = meta.startAt, serverNow >= startAt {
                transport.set(RoomPaths.meta(code) + "/status", value: RoomStatus.playing.rawValue)
                self.meta?.status = .playing
            }
            if status == .playing, var e = engine {
                // A seated player whose input node is missing (dropped connection) is skipped,
                // not zeroed, so their tug watermark survives until they are back.
                let list = players.filter { $0.slot >= 0 }.compactMap { p -> EnginePlayer? in
                    guard let inp = p.id == myId ? myInput : inputs[p.id] else { return nil }
                    return EnginePlayer(id: p.id, team: p.team, slot: p.slot, pull: inp.pull, tugs: inp.tugs)
                }
                let outcome = e.step(dt: dt, players: list)
                engine = e
                display = e.state
                if let outcome {
                    finishRound(outcome, finalState: e.state)
                } else if now - lastPublish >= GameConfig.statePublishInterval {
                    publishSeq += 1
                    var s = e.state
                    s.seq = publishSeq
                    s.t = serverNow
                    transport.set(RoomPaths.state(code), value: RTCodec.encode(s))
                    lastPublish = now
                }
            }
        } else if let net = netState, status == .playing || status == .finished {
            // Glide toward the host's state, extrapolated by its velocities so the rope
            // keeps moving smoothly between updates.
            let age = clamp(now - netReceivedAt, 0, 0.3)
            let k = 1 - exp(-dt * 12)
            display.x += (net.x + net.vx * age - display.x) * k
            display.vx = net.vx
            display.holeR += (net.holeR - display.holeR) * k
            var radii: [String: Double] = [:]
            for (id, r) in net.radii {
                let target = r + (net.radVel[id] ?? 0) * age
                let current = display.radii[id] ?? target
                radii[id] = current + (target - current) * k
            }
            display.radii = radii
            display.radVel = net.radVel
            display.elim = net.elim
            display.elapsed = net.elapsed
            display.seq = net.seq
        }

        for id in display.elim.keys where elimSeen[id] == nil { elimSeen[id] = now }

        bots?.tick(now: now, playing: status == .playing)
        updateCamera(meta: meta, dt: dt)
        frame = makeFrame(meta: meta, now: now)
    }

    // MARK: - Camera

    /// Keep my dot comfortably in view together with the centre line / hole.
    private func updateCamera(meta: RoomMeta, dt: Double) {
        var target = CameraState()
        target.initialized = true
        let w = viewport.width, h = viewport.height
        let active = amParticipating && !amEliminated

        switch meta.mode {
        case .linear:
            var mePos = CGPoint.zero
            if active, let me { mePos = Layout.linearPosition(team: me.team, slot: me.slot, ropeX: display.x) }
            let cx = mePos.x * 0.55
            let half = max(abs(mePos.x - cx), abs(cx)) + 72
            target.center = CGPoint(x: cx, y: 0)
            target.zoom = clamp((w / 2 - 12) / half, 0.35, 1.25)
            target.rotation = 0

        case .circular:
            let inner = display.holeR
            let outer = GameConfig.outerRadius
            if active, let me {
                // Sit between the middle of the ledge and my dot, and frame both edges of
                // the ledge, so the hole and the outer pit are always on screen.
                let c = (GameConfig.bandMiddle(hole: inner) + display.radius(myId)) / 2
                let half = max(c - inner, outer - c) + GameConfig.dotRadius + 12
                let dir = Layout.outward(slot: me.slot, count: meta.slotCount)
                target.center = CGPoint(x: dir.dx * c, y: dir.dy * c)
                target.zoom = clamp((h / 2 - 14) / half, 0.2, 1.6)
                // Rotate the world so my pulling direction points straight up.
                target.rotation = -.pi / 2 - Layout.ringAngle(slot: me.slot, count: meta.slotCount)
            } else {
                target.center = .zero
                target.zoom = clamp((min(w, h) / 2 - 12) / (outer + GameConfig.dotRadius), 0.15, 1.2)
                target.rotation = camera.initialized ? camera.rotation : 0
            }
        }
        camera.approach(target, dt: dt)
    }

    private func makeFrame(meta: RoomMeta, now: TimeInterval) -> RenderFrame {
        var f = RenderFrame()
        f.mode = meta.mode
        f.teamMode = meta.teamMode
        f.status = meta.status
        f.ropeX = display.x
        f.holeR = display.holeR
        f.outerR = GameConfig.outerRadius
        f.myId = myId
        f.myTeam = me?.team ?? Team.none
        f.myColorIndex = me?.colorIndex ?? 0
        f.amParticipating = amParticipating
        f.amEliminated = amEliminated
        f.myPullDirectionWorld = pullDirectionWorld()
        f.myPull = myInput.pull
        f.camera = camera
        if meta.status == .countdown, let startAt = meta.startAt {
            f.countdownSeconds = max(0, Int(ceil((startAt - serverNow) / 1000)))
        }
        f.elapsed = display.elapsed
        f.suddenDeath = meta.mode == .circular && display.elapsed > GameConfig.holeRushDelay
        f.winner = meta.winner
        f.tugPulse = clamp(1 - (now - lastTugAt) / 0.35, 0, 1)
        f.isConnected = transport.isConnected

        var dots: [DotSprite] = []
        for p in players where p.slot >= 0 {
            let pos: CGPoint
            switch meta.mode {
            case .linear: pos = Layout.linearPosition(team: p.team, slot: p.slot, ropeX: display.x)
            case .circular: pos = Layout.circularPosition(slot: p.slot, count: meta.slotCount,
                                                          radius: display.radius(p.id))
            }
            var progress = 0.0
            if display.elim[p.id] != nil {
                let since = elimSeen[p.id].map { now - $0 } ?? 1
                progress = clamp(since / 0.7, 0, 1)
            } else {
                f.aliveTotal += 1
                if p.team == .red { f.aliveRed += 1 } else if p.team == .blue { f.aliveBlue += 1 }
            }
            dots.append(DotSprite(id: p.id, slot: p.slot, position: pos, team: p.team, colorIndex: p.colorIndex,
                                  initials: p.initials, name: p.name, isMe: p.id == myId,
                                  elimProgress: progress))
        }
        f.dots = dots
        f.waitingCount = players.filter { $0.slot < 0 }.count
        return f
    }
}
