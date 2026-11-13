import Foundation

/// An in-memory stand-in for the realtime database: same paths, same observer semantics
/// (an observer fires once immediately, then on every change beneath or above its path).
/// Used for practice-vs-bots and for running the game without a Firebase project.
@MainActor
final class LocalTransport: RoomTransport {
    let myId = "local-me"
    var serverOffsetMs: Double { 0 }
    var isOnline: Bool { false }
    var isConnected: Bool { true }

    private var tree: [String: Any] = [:]
    private var observers: [ObserverToken: (path: [String], handler: @MainActor (Any?) -> Void)] = [:]
    private var nextToken: ObserverToken = 1

    private func parts(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    private func get(_ path: [String]) -> Any? {
        var node: Any? = tree
        for key in path {
            guard let dict = node as? [String: Any] else { return nil }
            node = dict[key]
        }
        return node
    }

    private func put(_ path: [String], _ value: Any?) {
        tree = (putInto(tree, path[...], value) as? [String: Any]) ?? [:]
    }

    private func putInto(_ node: Any?, _ path: ArraySlice<String>, _ value: Any?) -> Any? {
        guard let key = path.first else { return value }
        var dict = node as? [String: Any] ?? [:]
        let child = putInto(dict[key], path.dropFirst(), value)
        if let child, !(child is NSNull), !((child as? [String: Any])?.isEmpty ?? false) {
            dict[key] = child
        } else {
            dict.removeValue(forKey: key)
        }
        return dict
    }

    private func notify(_ changed: [String]) {
        for (_, obs) in observers {
            let n = min(obs.path.count, changed.count)
            if Array(obs.path.prefix(n)) == Array(changed.prefix(n)) {
                obs.handler(get(obs.path))
            }
        }
    }

    func set(_ path: String, value: Any?) {
        let p = parts(path)
        put(p, value)
        notify(p)
    }

    func update(_ values: [String: Any]) {
        var touched: [[String]] = []
        for (k, v) in values {
            let p = parts(k)
            put(p, v is NSNull ? nil : v)
            touched.append(p)
        }
        // One notification per observer, not one per key.
        for (_, obs) in observers {
            let hit = touched.contains { changed in
                let n = min(obs.path.count, changed.count)
                return Array(obs.path.prefix(n)) == Array(changed.prefix(n))
            }
            if hit { obs.handler(get(obs.path)) }
        }
    }

    func read(_ path: String) async -> Any? { get(parts(path)) }

    func observe(_ path: String, handler: @escaping @MainActor (Any?) -> Void) -> ObserverToken {
        let token = nextToken
        nextToken += 1
        let p = parts(path)
        observers[token] = (p, handler)
        handler(get(p))
        return token
    }

    func removeObserver(_ token: ObserverToken) { observers.removeValue(forKey: token) }
    func onDisconnectRemove(_ path: String) {}
    func onDisconnectSet(_ path: String, value: Any) {}
    func cancelDisconnectOperations(_ path: String) {}

    func compareAndSet(_ path: String, expected: @escaping @Sendable (Any?) -> Bool, value: Any) async -> Bool {
        let p = parts(path)
        guard expected(get(p)) else { return false }
        put(p, value)
        notify(p)
        return true
    }
}
