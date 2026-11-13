import Foundation
import FirebaseAuth

/// Anonymous sign-in, the same approach as the class AnonLobbyCloud / MoLobbyAnon examples.
/// Firebase remembers the anonymous user across launches, so the uid is stable per install.
enum AuthService {
    static func signIn() async throws -> String {
        if let user = Auth.auth().currentUser { return user.uid }
        let result = try await Auth.auth().signInAnonymously()
        return result.user.uid
    }
}
