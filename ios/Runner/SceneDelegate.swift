import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    handleIncomingUrlContexts(connectionOptions.urlContexts, source: "scene_will_connect")
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    super.scene(scene, openURLContexts: URLContexts)
    handleIncomingUrlContexts(URLContexts, source: "scene_open_url")
  }

  private func handleIncomingUrlContexts(
    _ urlContexts: Set<UIOpenURLContext>,
    source: String
  ) {
    for context in urlContexts {
      _ = AppDelegate.handleIncomingUrl(context.url, source: source)
    }
  }
}
