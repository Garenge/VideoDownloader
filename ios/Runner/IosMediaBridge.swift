import Flutter
import JavaScriptCore
import UIKit

final class IosMediaBridge {
  private let merger = IosMediaMerger()
  private let exporter = IosFileExporter()

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "videodownloader/ios_media", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [self] call, result in
      switch call.method {
      case "xToken":
        guard let id = call.arguments as? String,
              !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }),
              id.count <= 25,
              let token = Self.xToken(id)
        else {
          result(FlutterError(code: "invalid_id", message: "X 帖子编号无效", details: nil))
          return
        }
        result(token)
      case "exportFile":
        exporter.export(path: call.arguments as? String, result: result)
      case "merge":
        merger.merge(arguments: call.arguments as? [String: String], result: result)
      case "cancelMerge":
        if let id = call.arguments as? String { merger.cancel(id: id) }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func xToken(_ id: String) -> String? {
    guard !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return JSContext()?.evaluateScript(
      "((Number('\(id)') / 1e15) * Math.PI).toString(36).replace(/(0+|\\.)/g, '')"
    )?.toString()
  }

  static func documentURL(_ path: String?) -> URL? {
    guard let path, path.hasPrefix("/"),
          let documents = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
          ).first
    else { return nil }
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    let root = documents.resolvingSymlinksInPath().standardizedFileURL.path
    return url.path.hasPrefix(root + "/") ? url : nil
  }
}
