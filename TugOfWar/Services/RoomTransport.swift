import Foundation

typealias ObserverToken = Int

/// The small slice of a realtime database the game needs. Paths are relative to the
/// app's root node and look like `rooms/ABCD/players/uid`. Values are plain JSON-ish
/// objects (dictionaries, arrays, numbers, strings), exactly what Firebase hands back.
///
/// Two implementations: `FirebaseTransport` (Realtime Database, like the class MoLobby
/// example) and `LocalTransport` (in-memory, for practice vs bots and for testing without
/// a Firebase project).
@MainActor
protocol RoomTransport: AnyObject {
    var myId: String { get }
    var serverOffsetMs: Double { get }
    var isOnline: Bool { get }

    func set(_ path: String, value: Any?)
    func update(_ values: [String: Any])
    func read(_ path: String) async -> Any?
    func observe(_ path: String, handler: @escaping @MainActor (Any?) -> Void) -> ObserverToken
    func removeObserver(_ token: ObserverToken)
    func onDisconnectRemove(_ path: String)
    func onDisconnectSet(_ path: String, value: Any)
    func cancelDisconnectOperations(_ path: String)
    /// Atomically write `value` if `expected(current)` holds. Returns true when committed.
    func compareAndSet(_ path: String, expected: @escaping @Sendable (Any?) -> Bool, value: Any) async -> Bool
}

extension RoomTransport {
    /// Current server time in ms (local clock corrected by the server offset).
    var serverNow: Double { Date().timeIntervalSince1970 * 1000 + serverOffsetMs }
}

enum RoomPaths {
    static func room(_ code: String) -> String { "rooms/\(code)" }
    static func meta(_ code: String) -> String { "rooms/\(code)/meta" }
    static func state(_ code: String) -> String { "rooms/\(code)/state" }
    static func players(_ code: String) -> String { "rooms/\(code)/players" }
    static func player(_ code: String, _ id: String) -> String { "rooms/\(code)/players/\(id)" }
    static func inputs(_ code: String) -> String { "rooms/\(code)/inputs" }
    static func input(_ code: String, _ id: String) -> String { "rooms/\(code)/inputs/\(id)" }
}

/// Codable <-> database value, via JSON so the same records work for Firebase and the local store.
enum RTCodec {
    static func encode<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return NSNull()
        }
        return obj
    }

    static func decode<T: Decodable>(_ any: Any?) -> T? {
        guard let any, !(any is NSNull) else { return nil }
        guard JSONSerialization.isValidJSONObject(any) || any is NSNumber || any is String,
              let data = try? JSONSerialization.data(withJSONObject: any, options: [.fragmentsAllowed]) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

enum RoomCode {
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")

    static func random() -> String {
        String((0..<4).map { _ in alphabet.randomElement()! })
    }

    /// Accepts "abcd", " ab-cd ", or a full join link.
    static func normalize(_ raw: String) -> String? {
        if let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           let code = JoinLink.code(from: url) {
            return code
        }
        let letters = raw.uppercased().filter { alphabet.contains($0) }
        return letters.count == 4 ? String(letters) : nil
    }
}
