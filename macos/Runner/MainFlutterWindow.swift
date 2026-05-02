import Cocoa
import FlutterMacOS

private let kRevealInFinderChannel = "videodownloader/reveal_in_finder"

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

    let fm = FileManager.default
    var isDir: ObjCBool = false
    // 规范化 `..`、多余 `/`、以及 `~`；避免与 Finder 实际展示路径不一致。
    let stdPath = (path as NSString).standardizingPath
    guard fm.fileExists(atPath: stdPath, isDirectory: &isDir) else {
      result(
        FlutterError(code: "not_found", message: "path does not exist", details: stdPath))
      return
    }

    let baseURL = URL(fileURLWithPath: stdPath, isDirectory: isDir.boolValue)
    // 与 Finder 一致地解析符号链接；`selectFile(_:inFileViewerRootedAtPath:)` 在含 symlink
    // 时容易打开错误根目录（例如只到用户家目录）。
    let targetURL = baseURL.resolvingSymlinksInPath()

    var resolvedIsDir: ObjCBool = false
    guard fm.fileExists(atPath: targetURL.path, isDirectory: &resolvedIsDir) else {
      result(
        FlutterError(
          code: "not_found", message: "resolved path does not exist", details: targetURL.path))
      return
    }

    let ok: Bool
    if resolvedIsDir.boolValue {
      ok = NSWorkspace.shared.open(targetURL)
    } else {
      // 与「在 Finder 中显示」同语义；新版 SDK 上为 Void，无法据返回值判断，失败时由 Dart 回退 `open -R`。
      NSWorkspace.shared.activateFileViewerSelecting([targetURL])
      ok = true
    }
    result(ok)
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerRevealInFinderChannel(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
