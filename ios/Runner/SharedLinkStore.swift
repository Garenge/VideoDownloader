import Foundation

/// Runner 与 Share Extension 通过 App Group 交接链接。
enum SharedLinkStore {
  private static let key = "pending_shared_url"

  private static var defaults: UserDefaults? {
    guard let group = Bundle.main.object(
      forInfoDictionaryKey: "VideoDownloaderAppGroup"
    ) as? String,
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: group
      ) != nil
    else { return nil }
    return UserDefaults(suiteName: group)
  }

  static func save(_ url: URL) -> Bool {
    guard let store = defaults else { return false }
    store.set(url.absoluteString, forKey: key)
    return store.synchronize()
  }

  static func take() -> URL? {
    guard let store = defaults, let text = store.string(forKey: key),
          let url = URL(string: text),
          ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    else { return nil }
    store.removeObject(forKey: key)
    store.synchronize()
    var components = URLComponents()
    components.scheme = "videodownloader"
    components.host = "parse"
    components.queryItems = [
      URLQueryItem(name: "url", value: url.absoluteString),
      URLQueryItem(name: "source", value: "share_extension"),
    ]
    return components.url
  }

  static func clear() {
    defaults?.removeObject(forKey: key)
    defaults?.synchronize()
  }
}
