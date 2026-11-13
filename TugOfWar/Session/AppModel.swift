import SwiftUI
import Observation

/// App-wide state: the local profile, the online connection, and the current room.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    enum OnlineStatus: Equatable {
        case connecting
        case ready
        case unavailable(String)
    }

    var profile = Profile.load() {
        didSet {
            profile.save()
            session?.updateProfile(profile)
        }
    }
    var online: OnlineStatus = .connecting
    var session: RoomSession?
    var busy = false
    var errorMessage: String?

    @ObservationIgnored private var transport: FirebaseTransport?
    @ObservationIgnored private var pendingJoinCode: String?
    @ObservationIgnored private var bootstrapped = false

    var isOnline: Bool { online == .ready }

    func bootstrap() async {
        guard !bootstrapped else { return }
        bootstrapped = true
        if FirebaseBootstrap.isConfigured {
            do {
                let uid = try await AuthService.signIn()
                transport = FirebaseTransport(uid: uid)
                online = .ready
            } catch {
                online = .unavailable("Sign-in failed: \(error.localizedDescription)")
            }
        } else {
            online = .unavailable(FirebaseBootstrap.unavailableReason)
        }
        if let code = pendingJoinCode, isOnline {
            pendingJoinCode = nil
            await join(code: code)
        }
        #if DEBUG
        await applyLaunchArguments()
        #endif
    }

    #if DEBUG
    /// Debug/demo hooks, e.g. `--practice=circular,individual --bots=5 --autostart --autotug`.
    private func applyLaunchArguments() async {
        // Also readable from the environment (`SIMCTL_CHILD_TUG_PRACTICE=circular,teams` with simctl).
        let env = ProcessInfo.processInfo.environment
        var args = ProcessInfo.processInfo.arguments
        if let v = env["TUG_PRACTICE"] { args.append("--practice=" + v) }
        if let v = env["TUG_BOTS"] { args.append("--bots=" + v) }
        if env["TUG_AUTOSTART"] != nil { args.append("--autostart") }
        if env["TUG_AUTOTUG"] != nil { args.append("--autotug") }
        guard let spec = args.first(where: { $0.hasPrefix("--practice=") }) else { return }
        let parts = spec.dropFirst("--practice=".count).split(separator: ",").map(String.init)
        let mode = GameMode(rawValue: parts.first ?? "") ?? .linear
        let teamMode = TeamMode(rawValue: parts.dropFirst().first ?? "") ?? .teams
        let bots = Int(args.first(where: { $0.hasPrefix("--bots=") })?.dropFirst("--bots=".count) ?? "") ?? 3
        await startPractice(mode: mode, teamMode: teamMode, bots: bots)
        session?.debugAutoTug = args.contains("--autotug")
        if args.contains("--autostart") {
            try? await Task.sleep(for: .seconds(1))
            session?.startRound()
        }
    }
    #endif

    /// `tugofwar://join/ABCD` from AirDrop or an NFC tag.
    func handle(url: URL) {
        guard let code = JoinLink.code(from: url) else { return }
        if session?.code == code { return }
        if busy {
            errorMessage = "Still joining another room. Open the link again in a moment."
            return
        }
        if session != nil { leaveRoom() }
        if isOnline {
            Task { await join(code: code) }
        } else {
            pendingJoinCode = code
            if case .unavailable(let why) = online { errorMessage = why }
        }
    }

    func createRoom(mode: GameMode, teamMode: TeamMode) async {
        guard let transport else { reportOffline(); return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        var code = RoomCode.random()
        for _ in 0..<5 {
            if await transport.read(RoomPaths.meta(code)) == nil { break }
            code = RoomCode.random()
        }
        let s = RoomSession(code: code, transport: transport, profile: profile, isPractice: false)
        await s.create(mode: mode, teamMode: teamMode)
        session?.leave()
        session = s
    }

    func join(code raw: String) async {
        guard let code = RoomCode.normalize(raw) else {
            errorMessage = "Room codes are 4 letters, like ABCD."
            return
        }
        guard let transport else { reportOffline(); return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let s = RoomSession(code: code, transport: transport, profile: profile, isPractice: false)
        do {
            try await s.join()
            session?.leave()
            session = s
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPractice(mode: GameMode, teamMode: TeamMode, bots: Int) async {
        let t = LocalTransport()
        let s = RoomSession(code: "SOLO", transport: t, profile: profile, isPractice: true)
        await s.create(mode: mode, teamMode: teamMode)
        s.addBots(count: bots)
        session?.leave()
        session = s
    }

    func leaveRoom() {
        session?.leave()
        session = nil
    }

    private func reportOffline() {
        if case .unavailable(let why) = online {
            errorMessage = why
        } else {
            errorMessage = "Still connecting. Try again in a moment."
        }
    }
}
