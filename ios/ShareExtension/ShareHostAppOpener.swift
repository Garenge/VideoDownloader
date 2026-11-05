import UIKit

@MainActor
enum ShareHostAppOpener {
  static func open(
    _ url: URL,
    from controller: UIViewController,
    completion: @escaping (Bool) -> Void
  ) {
    guard let application = findApplication(from: controller) else {
      openViaExtension(url, context: controller.extensionContext, completion: completion)
      return
    }
    print("ios/ShareExtension/ShareHostAppOpener.swift#open: trying UIApplication.open")
    application.open(url, options: [:]) { success in
      print("ios/ShareExtension/ShareHostAppOpener.swift#open: application result=\(success)")
      if success {
        completion(true)
      } else {
        openViaExtension(url, context: controller.extensionContext, completion: completion)
      }
    }
  }

  private static func findApplication(from responder: UIResponder) -> UIApplication? {
    var current: UIResponder? = responder
    while let candidate = current {
      if let application = candidate as? UIApplication {
        print("ios/ShareExtension/ShareHostAppOpener.swift#findApplication: found in responder chain")
        return application
      }
      current = candidate.next
    }
    // 分享扩展的响应链未必包含 UIApplication，使用运行时获取当前进程的实例。
    let selector = NSSelectorFromString("sharedApplication")
    guard UIApplication.responds(to: selector) else { return nil }
    let application = UIApplication.perform(selector)?.takeUnretainedValue() as? UIApplication
    print(
      "ios/ShareExtension/ShareHostAppOpener.swift#findApplication: runtime instance available=\(application != nil)"
    )
    return application
  }

  private static func openViaExtension(
    _ url: URL,
    context: NSExtensionContext?,
    completion: @escaping (Bool) -> Void
  ) {
    guard let context else {
      print("ios/ShareExtension/ShareHostAppOpener.swift#openViaExtension: no extension context")
      completion(false)
      return
    }
    context.open(url) { success in
      DispatchQueue.main.async {
        print(
          "ios/ShareExtension/ShareHostAppOpener.swift#openViaExtension: extension result=\(success)"
        )
        completion(success)
      }
    }
  }
}
