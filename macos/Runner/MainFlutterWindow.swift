import Cocoa
import FlutterMacOS
import JavaScriptCore

private let kRevealInFinderChannel = "videodownloader/reveal_in_finder"
private let kXLoginChannel = "videodownloader/x_login"

private func revealLogLabel(_ path: String) -> String {
  let label = URL(fileURLWithPath: path).lastPathComponent
  return label.isEmpty ? "-" : label
}

private func registerRevealInFinderChannel(_ messenger: FlutterBinaryMessenger) {
  let channel = FlutterMethodChannel(name: kRevealInFinderChannel, binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    guard call.method == "reveal" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let path = call.arguments as? String, !path.isEmpty else {
      result(
        FlutterError(code: "bad_args", message: "reveal requires non-empty path string", details: nil))
      return
    }
    let requestLabel = revealLogLabel(path)
    NSLog("macos/Runner/MainFlutterWindow.swift#reveal: request path=%@", requestLabel)

    let fm = FileManager.default
    var isDir: ObjCBool = false
    // 规范化 `..`、多余 `/`、以及 `~`；避免与 Finder 实际展示路径不一致。
    let stdPath = (path as NSString).standardizingPath
    let stdLabel = revealLogLabel(stdPath)
    guard fm.fileExists(atPath: stdPath, isDirectory: &isDir) else {
      NSLog("macos/Runner/MainFlutterWindow.swift#reveal: stdPath missing path=%@", stdLabel)
      result(
        FlutterError(code: "not_found", message: "path does not exist", details: stdPath))
      return
    }
    NSLog(
      "macos/Runner/MainFlutterWindow.swift#reveal: standardized path=%@ isDir=%@",
      stdLabel,
      isDir.boolValue.description)

    let baseURL = URL(fileURLWithPath: stdPath, isDirectory: isDir.boolValue)
    // 与 Finder 一致地解析符号链接；`selectFile(_:inFileViewerRootedAtPath:)` 在含 symlink
    // 时容易打开错误根目录（例如只到用户家目录）。
    let targetURL = baseURL.resolvingSymlinksInPath()
    let targetLabel = revealLogLabel(targetURL.path)

    var resolvedIsDir: ObjCBool = false
    guard fm.fileExists(atPath: targetURL.path, isDirectory: &resolvedIsDir) else {
      NSLog(
        "macos/Runner/MainFlutterWindow.swift#reveal: resolved path missing path=%@",
        targetLabel)
      result(
        FlutterError(
          code: "not_found", message: "resolved path does not exist", details: targetURL.path))
      return
    }
    NSLog(
      "macos/Runner/MainFlutterWindow.swift#reveal: resolved path=%@ isDir=%@",
      targetLabel,
      resolvedIsDir.boolValue.description)

    let ok: Bool
    if resolvedIsDir.boolValue {
      ok = NSWorkspace.shared.open(targetURL)
      NSLog(
        "macos/Runner/MainFlutterWindow.swift#reveal: NSWorkspace.open ok=%@ path=%@",
        ok.description,
        targetLabel)
    } else {
      // 与「在 Finder 中显示」同语义；新版 SDK 上为 Void，无法据返回值判断，失败时由 Dart 回退 `open -R`。
      NSWorkspace.shared.activateFileViewerSelecting([targetURL])
      ok = true
      NSLog(
        "macos/Runner/MainFlutterWindow.swift#reveal: activateFileViewerSelecting path=%@",
        targetLabel)
    }
    result(ok)
  }
}

class MainFlutterWindow: NSWindow {
  private let xLoginController = XLoginWindowController()

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerRevealInFinderChannel(flutterViewController.engine.binaryMessenger)
    let xLoginChannel = FlutterMethodChannel(
      name: kXLoginChannel,
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    xLoginChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "App window is unavailable", details: nil))
        return
      }
      switch call.method {
      case "xToken":
        guard let id = call.arguments as? String, !id.isEmpty,
              id.allSatisfy({ $0.isASCII && $0.isNumber })
        else {
          result(FlutterError(code: "bad_args", message: "Invalid X status ID", details: nil))
          return
        }
        result(JSContext()?.evaluateScript(
          "((Number('\(id)') / 1e15) * Math.PI).toString(36).replace(/(0+|\\.)/g, '')"
        )?.toString())
      case "login":
        self.xLoginController.openLogin { authenticated in result(authenticated) }
      case "exportCookies":
        self.xLoginController.exportCookies { result($0) }
      case "fetchLikes":
        let arguments = call.arguments as? [String: Any]
        self.xLoginController.fetchLikes(cursor: arguments?["cursor"] as? String) { result($0) }
      case "cancelLikes":
        self.xLoginController.cancelLikes()
        result(nil)
      case "isAuthenticated":
        self.xLoginController.isAuthenticated { result($0) }
      case "accountStatus":
        self.xLoginController.accountStatus { result($0) }
      case "logout":
        self.xLoginController.logout { result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
