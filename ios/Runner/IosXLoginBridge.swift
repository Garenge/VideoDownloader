import Flutter
import UIKit

final class IosXLoginBridge {
  private let session = IosXSession()
  private var browser: IosXBrowserController?

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "videodownloader/x_login", binaryMessenger: messenger)
    channel.setMethodCallHandler { [self] call, result in
      switch call.method {
      case "login":
        open(url: URL(string: "https://x.com/i/flow/login")!, statusID: nil, result: result)
      case "accountStatus":
        session.status(completion: result)
      case "isAuthenticated":
        session.status { result($0["authenticated"]) }
      case "logout":
        session.logout { result(nil) }
      case "configureProxy":
        do {
          try session.configureProxy(call.arguments as? String)
          result(nil)
        } catch {
          result(FlutterError(code: "proxy_unavailable", message: error.localizedDescription, details: nil))
        }
      case "resolveVideo":
        guard let value = call.arguments as? String, let url = URL(string: value),
              url.scheme == "https", let host = url.host, IosXSession.isXDomain(host),
              let id = Self.statusID(url)
        else {
          result(FlutterError(code: "invalid_url", message: "X 帖子链接无效", details: nil))
          return
        }
        session.status { [self] status in
          guard status["authenticated"] as? Bool == true else {
            result(FlutterError(code: "login_required", message: "请先通过右上角账号入口登录 X", details: nil))
            return
          }
          open(url: URL(string: "https://x.com/i/status/\(id)")!, statusID: id, result: result)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func statusID(_ url: URL) -> String? {
    let parts = url.pathComponents
    guard let index = parts.firstIndex(of: "status"), parts.indices.contains(index + 1) else {
      return nil
    }
    let id = parts[index + 1]
    return !id.isEmpty && id.count <= 25 && id.allSatisfy({ $0.isASCII && $0.isNumber }) ? id : nil
  }

  private func open(url: URL, statusID: String?, result: @escaping FlutterResult) {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard browser == nil,
          let presenter = scenes.filter({ $0.activationState == .foregroundActive })
            .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController,
          presenter.presentedViewController == nil
    else {
      result(FlutterError(code: "busy", message: "请先关闭当前弹窗后重试", details: nil))
      return
    }
    let controller = IosXBrowserController(session: session, target: url, statusID: statusID) {
      [weak self] value in
      self?.browser = nil
      result(value)
    }
    browser = controller
    let navigation = UINavigationController(rootViewController: controller)
    navigation.isModalInPresentation = true
    presenter.present(navigation, animated: true)
  }
}
