import Cocoa
import WebKit

final class XLoginWindowController: NSObject, NSWindowDelegate, WKHTTPCookieStoreObserver,
  WKNavigationDelegate
{
  private static let accountHandleKey = "videodownloader.xAccountHandle"
  private static let displayNameKey = "videodownloader.xDisplayName"
  private let dataStore = WKWebsiteDataStore.default()
  private var window: NSWindow?
  private var webView: WKWebView?
  private let likesController = XLikesController()
  private var loginCompletions: [(Bool) -> Void] = []
  private var isClosingAfterLogin = false

  func openLogin(completion: @escaping (Bool) -> Void) {
    loginCompletions.append(completion)
    if let window {
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
      return
    }

    isClosingAfterLogin = false
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = dataStore
    dataStore.httpCookieStore.add(self)
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "登录 X"
    window.contentView = webView
    window.delegate = self
    self.webView = webView
    self.window = window
    webView.load(URLRequest(url: URL(string: "https://x.com/i/flow/login")!))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func exportCookies(completion: @escaping (String) -> Void) {
    dataStore.httpCookieStore.getAllCookies { cookies in
      let lines = cookies
        .filter { Self.isXCookie($0) }
        .map(Self.netscapeLine)
      completion(([
        "# Netscape HTTP Cookie File",
        "# Generated temporarily by VideoDownloader",
      ] + lines).joined(separator: "\n") + "\n")
    }
  }

  func fetchLikes(cursor: String?, completion: @escaping (String) -> Void) {
    likesController.fetch(cursor: cursor, completion: completion)
  }

  func cancelLikes() {
    likesController.cancel()
  }

  func isAuthenticated(completion: @escaping (Bool) -> Void) {
    dataStore.httpCookieStore.getAllCookies { cookies in
      completion(cookies.contains { $0.name == "auth_token" && Self.isXCookie($0) })
    }
  }

  func accountStatus(completion: @escaping ([String: Any]) -> Void) {
    dataStore.httpCookieStore.getAllCookies { cookies in
      let authenticated = cookies.contains {
        $0.name == "auth_token" && Self.isXCookie($0)
      }
      completion([
        "authenticated": authenticated,
        "handle": authenticated
          ? (UserDefaults.standard.string(forKey: Self.accountHandleKey) as Any? ?? NSNull())
          : NSNull(),
        "displayName": authenticated
          ? (UserDefaults.standard.string(forKey: Self.displayNameKey) as Any? ?? NSNull())
          : NSNull(),
      ])
    }
  }

  func logout(completion: @escaping () -> Void) {
    likesController.cancel()
    let store = dataStore
    let group = DispatchGroup()
    store.httpCookieStore.getAllCookies { cookies in
      for cookie in cookies where Self.isXCookie(cookie) {
        group.enter()
        store.httpCookieStore.delete(cookie) { group.leave() }
      }
      group.enter()
      store.fetchDataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes()) { records in
        let xRecords = records.filter {
          Self.isXDomain($0.displayName)
        }
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: xRecords) {
          group.leave()
        }
      }
      group.notify(queue: .main) {
        UserDefaults.standard.removeObject(forKey: Self.accountHandleKey)
        UserDefaults.standard.removeObject(forKey: Self.displayNameKey)
        completion()
      }
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    captureAccountDetails(from: webView, closeWhenDone: false)
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    cookieStore.getAllCookies { [weak self] cookies in
      guard let self,
        cookies.contains(where: { $0.name == "auth_token" && Self.isXCookie($0) })
      else { return }
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window != nil, !self.isClosingAfterLogin else { return }
        self.isClosingAfterLogin = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
          guard let self, let webView = self.webView else { return }
          self.captureAccountDetails(from: webView, closeWhenDone: true)
        }
      }
    }
  }

  private func captureAccountDetails(from webView: WKWebView, closeWhenDone: Bool) {
    let script = """
      (() => {
        const link = document.querySelector('a[data-testid="AppTabBar_Profile_Link"]');
        if (!link) return null;
        const parts = (link.getAttribute('href') || '').split('/').filter(Boolean);
        const handle = parts.length ? '@' + parts[parts.length - 1] : null;
        const text = (link.innerText || '').split('\\n').map(value => value.trim()).filter(Boolean);
        return { handle, displayName: text.length > 1 ? text[0] : null };
      })()
      """
    webView.evaluateJavaScript(script) { [weak self] result, _ in
      guard let self else { return }
      if let account = result as? [String: Any] {
        if let handle = account["handle"] as? String, !handle.isEmpty {
          UserDefaults.standard.set(handle, forKey: Self.accountHandleKey)
        }
        if let displayName = account["displayName"] as? String, !displayName.isEmpty {
          UserDefaults.standard.set(displayName, forKey: Self.displayNameKey)
        }
      }
      if closeWhenDone {
        DispatchQueue.main.async { [weak self] in self?.window?.close() }
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    dataStore.httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self else { return }
      let authenticated = cookies.contains {
        $0.name == "auth_token" && Self.isXCookie($0)
      }
      let completions = self.loginCompletions
      self.loginCompletions.removeAll()
      self.window = nil
      self.webView = nil
      self.dataStore.httpCookieStore.remove(self)
      completions.forEach { $0(authenticated) }
    }
  }

  private static func isXCookie(_ cookie: HTTPCookie) -> Bool {
    isXDomain(cookie.domain)
  }

  private static func isXDomain(_ value: String) -> Bool {
    let domain = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    return domain == "x.com" || domain.hasSuffix(".x.com")
      || domain == "twitter.com" || domain.hasSuffix(".twitter.com")
  }

  private static func netscapeLine(_ cookie: HTTPCookie) -> String {
    let domain = cookie.isHTTPOnly ? "#HttpOnly_\(cookie.domain)" : cookie.domain
    let includeSubdomains = cookie.domain.hasPrefix(".") ? "TRUE" : "FALSE"
    let secure = cookie.isSecure ? "TRUE" : "FALSE"
    let expires = cookie.expiresDate.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
    return [domain, includeSubdomains, cookie.path, secure, expires, cookie.name, cookie.value]
      .joined(separator: "\t")
  }
}
