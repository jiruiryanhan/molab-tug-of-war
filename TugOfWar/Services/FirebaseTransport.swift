import Foundation
import FirebaseCore
import FirebaseDatabase

enum FirebaseBootstrap {
    static private(set) var isConfigured = false
    static private(set) var unavailableReason = "Add GoogleService-Info.plist to the TugOfWar folder to play online."

    /// Configure Firebase only when a config file is present, so the app still runs
    /// (practice mode) in a fresh checkout without one.
    static func configureIfPossible() {
        guard FirebaseApp.app() == nil else { isConfigured = true; return }
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
              let options = FirebaseOptions(contentsOfFile: path) else { return }
        guard let url = options.databaseURL, !url.isEmpty else {
            unavailableReason = "GoogleService-Info.plist has no DATABASE_URL. Enable Realtime Database in the Firebase console and download the plist again."
            return
        }
        FirebaseApp.configure(options: options)
        isConfigured = true
    }
}

/// Realtime Database transport. Mirrors how the class MoLobby example talks to Firebase:
/// `Database.database().reference()`, `observe(.value)`, `onDisconnect…`.
@MainActor
final class FirebaseTransport: RoomTransport {
    let myId: String
    private(set) var serverOffsetMs: Double = 0
    private(set) var isConnected = false
    var isOnline: Bool { true }

    private let root: DatabaseReference
    private var handles: [ObserverToken: (DatabaseReference, DatabaseHandle)] = [:]
    private var nextToken: ObserverToken = 1

    init(uid: String) {
        myId = uid
        let db = Database.database()
        root = db.reference().child("tug")
        db.reference(withPath: ".info/serverTimeOffset").observe(.value) { [weak self] snap in
            self?.serverOffsetMs = (snap.value as? NSNumber)?.doubleValue ?? 0
        }
        db.reference(withPath: ".info/connected").observe(.value) { [weak self] snap in
            let connected = (snap.value as? Bool) ?? false
            if let self, self.isConnected, !connected {
                // Writes queued while offline would replay over a new host's state on reconnect.
                db.purgeOutstandingWrites()
            }
            self?.isConnected = connected
        }
    }

    func set(_ path: String, value: Any?) {
        if let value, !(value is NSNull) {
            root.child(path).setValue(value)
        } else {
            root.child(path).removeValue()
        }
    }

    func update(_ values: [String: Any]) {
        root.updateChildValues(values)
    }

    func read(_ path: String) async -> Any? {
        guard let snap = try? await root.child(path).getData() else { return nil }
        let v = snap.value
        return v is NSNull ? nil : v
    }

    func observe(_ path: String, handler: @escaping @MainActor (Any?) -> Void) -> ObserverToken {
        let ref = root.child(path)
        let handle = ref.observe(.value) { snap in
            let v = snap.value
            handler(v is NSNull ? nil : v)
        }
        let token = nextToken
        nextToken += 1
        handles[token] = (ref, handle)
        return token
    }

    func removeObserver(_ token: ObserverToken) {
        guard let (ref, handle) = handles.removeValue(forKey: token) else { return }
        ref.removeObserver(withHandle: handle)
    }

    func onDisconnectRemove(_ path: String) {
        root.child(path).onDisconnectRemoveValue()
    }

    func onDisconnectSet(_ path: String, value: Any) {
        root.child(path).onDisconnectSetValue(value)
    }

    func cancelDisconnectOperations(_ path: String) {
        root.child(path).cancelDisconnectOperations()
    }

    func compareAndSet(_ path: String, expected: @escaping @Sendable (Any?) -> Bool, value: Any) async -> Bool {
        await Self.runTransaction(on: root.child(path), expected: expected, value: value)
    }

    /// Firebase runs the transaction block on its own queue, so build it off the main actor.
    nonisolated private static func runTransaction(on ref: DatabaseReference,
                                                   expected: @escaping @Sendable (Any?) -> Bool,
                                                   value: Any) async -> Bool {
        await withCheckedContinuation { cont in
            ref.runTransactionBlock({ data in
                let current = data.value is NSNull ? nil : data.value
                guard expected(current) else { return TransactionResult.abort() }
                data.value = value
                return TransactionResult.success(withValue: data)
            }, andCompletionBlock: { _, committed, _ in
                cont.resume(returning: committed)
            }, withLocalEvents: false)
        }
    }
}
