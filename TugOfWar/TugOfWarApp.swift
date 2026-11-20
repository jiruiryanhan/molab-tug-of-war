import SwiftUI
import UIKit

@main
struct TugOfWarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppModel.shared

    init() {
        FirebaseBootstrap.configureIfPossible()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .task { await app.bootstrap() }
                .onOpenURL { url in app.handle(url: url) }
        }
    }
}

/// Holds the orientations the app currently allows. A round is played in landscape, so the
/// game screen narrows this to landscape and widens it again on the way out.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var allowed: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.allowed
    }
}

enum OrientationLock {
    static let menus: UIInterfaceOrientationMask = [.portrait, .landscapeLeft, .landscapeRight]
    static let game: UIInterfaceOrientationMask = [.landscapeLeft, .landscapeRight]

    /// Ask iOS to rotate to one of `mask`, and keep it there until this is called again.
    static func set(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.allowed = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
