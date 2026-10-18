import CarPlay
import UIKit

/// Entry point for the CarPlay navigation scene (declared in Info.plist and returned by
/// `AppDelegate`). Requires the `com.apple.developer.carplay-maps` entitlement, which
/// Apple grants per app on request.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CarPlayController?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        MainActor.assumeIsolated {
            let c = CarPlayController(interfaceController: interfaceController, window: window, model: .shared)
            controller = c
            c.connect()
            AppModel.shared.setCarPlayConnected(true)
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        MainActor.assumeIsolated {
            controller?.disconnect()
            controller = nil
            AppModel.shared.setCarPlayConnected(false)
        }
    }
}
