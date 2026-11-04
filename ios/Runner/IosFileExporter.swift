import Flutter
import UIKit

final class IosFileExporter {
  func export(path: String?, result: @escaping FlutterResult) {
    guard let url = IosMediaBridge.documentURL(path),
          FileManager.default.fileExists(atPath: url.path)
    else {
      result(FlutterError(code: "missing_file", message: "下载文件不存在", details: nil))
      return
    }
    guard let presenter = Self.presenter(), presenter.presentedViewController == nil else {
      result(FlutterError(code: "unavailable", message: "请先关闭当前弹窗后重试", details: nil))
      return
    }
    let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
    if let popover = sheet.popoverPresentationController {
      popover.sourceView = presenter.view
      popover.sourceRect = CGRect(
        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY,
        width: 1, height: 1
      )
      popover.permittedArrowDirections = []
    }
    sheet.completionWithItemsHandler = { _, _, _, error in
      if let error {
        result(FlutterError(code: "export_failed", message: error.localizedDescription, details: nil))
      } else {
        result(nil)
      }
    }
    presenter.present(sheet, animated: true)
  }

  private static func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var controller = scenes.filter { $0.activationState == .foregroundActive }
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}
