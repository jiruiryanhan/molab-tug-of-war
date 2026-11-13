import SwiftUI

@main
struct TugOfWarApp: App {
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
