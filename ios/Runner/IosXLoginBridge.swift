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
          open(url: Self.postURL(url, statusID: id), statusID: id, result: result)
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

  static func postURL(_ url: URL, statusID: String) -> URL {
    let parts = url.pathComponents
    let index = parts.firstIndex(of: "status")!
    let path = parts.prefix(index + 1).dropFirst().joined(separator: "/")
    return URL(string: "https://x.com/\(path)/\(statusID)")!
  }

  private func open(
    url: URL, statusID: String?, result: @escaping FlutterResult, attempt: Int = 0
  ) {
    guard browser == nil else {
      result(FlutterError(code: "busy", message: "正在登录或读取 X 视频，请等待当前操作完成", details: nil))
      return
    }
    guard let presenter = readyPresenter() else {
      retryOpen(url: url, statusID: statusID, result: result, attempt: attempt)
      return
    }
    guard presenter.presentedViewController == nil else {
      retryOpen(url: url, statusID: statusID, result: result, attempt: attempt)
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

  private func readyPresenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let presenter = scenes.filter({ $0.activationState == .foregroundActive })
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController,
      presenter.viewIfLoaded?.window != nil,
      !presenter.isBeingPresented, !presenter.isBeingDismissed,
      presenter.transitionCoordinator == nil,
      presenter.presentedViewController?.isBeingDismissed != true
    else { return nil }
    return presenter
  }

  private func retryOpen(
    url: URL, statusID: String?, result: @escaping FlutterResult, attempt: Int
  ) {
    guard attempt < 30 else {
      print("ios/Runner/IosXLoginBridge.swift#retryOpen: foreground UI unavailable after waiting")
      let occupied = readyPresenter()?.presentedViewController != nil
      result(FlutterError(
        code: occupied ? "busy" : "not_ready",
        message: occupied ? "请先关闭当前弹窗后重试" : "应用界面尚未就绪，请回到主界面后重新解析",
        details: nil
      ))
      return
    }
    if attempt == 0 {
      print("ios/Runner/IosXLoginBridge.swift#retryOpen: waiting for foreground UI")
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
      open(url: url, statusID: statusID, result: result, attempt: attempt + 1)
    }
  }
}
