import UIKit

/// Turns the app to landscape for the player's full screen, and back.
@MainActor
enum Orientation {
    static func apply(landscape: Bool) {
        AppDelegate.orientations = landscape ? .landscape : .allButUpsideDown
        guard let scene = windowScene else { return }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        let wanted: UIInterfaceOrientationMask = landscape ? .landscape : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: wanted)) { _ in }
    }

    static var windowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }

    /// The controller to present system sheets from.
    static var topController: UIViewController? {
        var top = windowScene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
