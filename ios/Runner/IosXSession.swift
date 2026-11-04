import Network
import WebKit

final class IosXSession {
  let store: WKWebsiteDataStore

  init(store: WKWebsiteDataStore = .default()) {
    self.store = store
  }

  static func isXDomain(_ value: String) -> Bool {
    let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return domain == "x.com" || domain.hasSuffix(".x.com")
      || domain == "twitter.com" || domain.hasSuffix(".twitter.com")
  }

  func status(completion: @escaping ([String: Any]) -> Void) {
    store.httpCookieStore.getAllCookies { cookies in
      let authenticated = cookies.contains {
        Self.isXDomain($0.domain) && $0.name == "auth_token" && !$0.value.isEmpty
          && ($0.expiresDate == nil || $0.expiresDate! > Date())
      }
      completion(["authenticated": authenticated])
    }
  }

  func logout(completion: @escaping () -> Void) {
    let group = DispatchGroup()
    store.httpCookieStore.getAllCookies { cookies in
      for cookie in cookies where Self.isXDomain(cookie.domain) {
        group.enter()
        self.store.httpCookieStore.delete(cookie) { group.leave() }
      }
      group.enter()
      self.store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
        self.store.removeData(
          ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
          for: records.filter { Self.isXDomain($0.displayName) }
        ) { group.leave() }
      }
      group.notify(queue: .main, execute: completion)
    }
  }

  func configureProxy(_ spec: String?) throws {
    guard #available(iOS 17.0, *) else {
      if let spec, !spec.isEmpty {
        throw NSError(domain: "IosXSession", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "iOS 15/16 的 X 登录网页需使用系统网络或 VPN，无法使用应用内代理",
        ])
      }
      return
    }
    guard let spec, !spec.isEmpty else {
      store.proxyConfigurations = []
      return
    }
    let normalized = spec.contains("://") ? spec : "http://\(spec)"
    guard let url = URLComponents(string: normalized),
          url.scheme == "http", let host = url.host, !host.isEmpty,
          let port = NWEndpoint.Port(rawValue: UInt16(exactly: url.port ?? 8080) ?? 0),
          port.rawValue > 0
    else {
      throw NSError(domain: "IosXSession", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "X 登录网页仅支持有效的 HTTP 代理地址",
      ])
    }
    let proxy = ProxyConfiguration(httpCONNECTProxy: .hostPort(host: .init(host), port: port))
    if let user = url.user {
      proxy.applyCredential(username: user.removingPercentEncoding ?? user,
                            password: url.password?.removingPercentEncoding ?? "")
    }
    store.proxyConfigurations = [proxy]
  }
}
