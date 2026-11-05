import Flutter
import QuickLook
import UIKit

final class IosFilePreviewer: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  private var url: URL?
  private weak var activeController: QLPreviewController?

  func open(path: String?, result: @escaping FlutterResult) {
    guard let url = IosMediaBridge.documentURL(path),
          FileManager.default.fileExists(atPath: url.path),
          QLPreviewController.canPreview(url as NSURL)
    else {
      result(FlutterError(code: "preview_unavailable", message: "文件不存在或不支持预览，请尝试分享或导出", details: nil))
      return
    }
    guard activeController == nil, let presenter = presenter(),
          !presenter.isBeingDismissed, !presenter.isBeingPresented
    else {
      result(FlutterError(code: "preview_busy", message: "请关闭当前预览后重试", details: nil))
      return
    }
    present(url: url, from: presenter, result: result)
  }

  private func present(url: URL, from presenter: UIViewController, result: @escaping FlutterResult) {
    self.url = url
    let controller = QLPreviewController()
    controller.dataSource = self
    controller.delegate = self
    activeController = controller
    print("ios/Runner/IosFilePreviewer.swift#present: 打开文件预览")
    presenter.present(controller, animated: true) { result(nil) }
  }

  func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
    return url == nil ? 0 : 1
  }

  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
    return url! as NSURL
  }

  func previewControllerDidDismiss(_ controller: QLPreviewController) {
    url = nil
    activeController = nil
  }

  private func presenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var controller = scenes.filter { $0.activationState == .foregroundActive }
      .flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}
