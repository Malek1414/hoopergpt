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
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if mask == .portrait {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        }
    }
}
