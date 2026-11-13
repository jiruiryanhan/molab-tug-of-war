import Foundation

/// `tugofwar://join/ABCD` – registered in Info.plist, so an AirDropped link or an NFC tag
/// carrying it opens straight into the room.
enum JoinLink {
    static let scheme = "tugofwar"

    static func url(code: String) -> URL {
        URL(string: "\(scheme)://join/\(code)")!
    }

    static func code(from url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        if let last = url.pathComponents.last, last.count == 4, url.host?.lowercased() == "join" {
            return last.uppercased()
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
           let code = items.first(where: { $0.name == "code" })?.value, code.count == 4 {
            return code.uppercased()
        }
        return nil
    }
}
