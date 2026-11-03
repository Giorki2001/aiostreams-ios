import SwiftUI

/// Only the orientations the app allows at the moment: the player asks for landscape.
final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppDelegate.orientations
    }
}

@main
struct AIOStreamsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(.brand)
                .onOpenURL { model.open(link: $0) }
        }
    }
}

extension Color {
    /// AIOStreams' brand purple (#6152DF).
    static let brand = Color(red: 97 / 255, green: 82 / 255, blue: 223 / 255)
    /// The brand lightened (#9D93FF), for text and symbols on glass over bright artwork.
    static let brandLight = Color(red: 157 / 255, green: 147 / 255, blue: 255 / 255)
    /// The page's own background (#070707).
    static let page = Color(red: 7 / 255, green: 7 / 255, blue: 7 / 255)
}
