import SwiftUI
import UIKit

/// Local player profile: name + optional tiny avatar, persisted in UserDefaults.
struct Profile: Equatable {
    var name: String
    var photo: String?            // base64 JPEG, ~96px square
    var invertTilt: Bool

    static let nameKey = "profile.name"
    static let photoKey = "profile.photo"
    static let invertKey = "profile.invertTilt"

    static func load() -> Profile {
        let d = UserDefaults.standard
        let name = d.string(forKey: nameKey) ?? Self.defaultName()
        return Profile(name: name, photo: d.string(forKey: photoKey), invertTilt: d.bool(forKey: invertKey))
    }

    func save() {
        let d = UserDefaults.standard
        d.set(name, forKey: Self.nameKey)
        d.set(photo, forKey: Self.photoKey)
        d.set(invertTilt, forKey: Self.invertKey)
    }

    static func defaultName() -> String {
        let device = UIDevice.current.name
        if device.count > 1 && device.count < 14 { return device }
        return "Player \(Int.random(in: 10...99))"
    }

    var initials: String { PlayerRecord.initials(for: name) }

    var photoImage: UIImage? { Profile.decode(photo) }

    static func decode(_ base64: String?) -> UIImage? {
        guard let base64, let data = Data(base64Encoded: base64) else { return nil }
        return UIImage(data: data)
    }

    /// Downscale a picked photo to a 96pt square JPEG so it fits comfortably in the database.
    static func encode(_ image: UIImage, side: CGFloat = 96) -> String? {
        let srcSide = min(image.size.width, image.size.height)
        let crop = CGRect(x: (image.size.width - srcSide) / 2, y: (image.size.height - srcSide) / 2,
                          width: srcSide, height: srcSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let scaled = renderer.image { _ in
            let scale = side / srcSide
            let drawRect = CGRect(x: -crop.minX * scale, y: -crop.minY * scale,
                                  width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: drawRect)
        }
        return scaled.jpegData(compressionQuality: 0.7)?.base64EncodedString()
    }
}
