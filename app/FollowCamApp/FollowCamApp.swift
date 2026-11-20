import SwiftUI

@main
struct FollowCamApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Watch turns with the phone, upright or sideways; every other tab stays
/// upright (the camera code assumes portrait). Nothing is ever forced
/// sideways: a forced rotation on a phone held upright lays the whole screen
/// on its side. Leaving Watch only turns the screen back upright.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientations
    }

    static func allow(_ mask: UIInterfaceOrientationMask) {
        orientations = mask
        // Next run-loop turn: on the first call the window does not exist yet,
        // and without this re-check a phone that is already sideways when
        // Watch opens would stay upright (no rotation event ever comes).
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                for window in scene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
                if mask == .portrait {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                }
            }
        }
    }
}
