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
  private var likesWebView: WKWebView?
  private var likesWindow: NSWindow?
  private var likesCompletion: ((String) -> Void)?
  private var likesAttempt = 0
  private var likesLastPostCount = 0
  private var likesStalledAttempts = 0
  private let likesMaxPosts = 100
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

  func fetchLikes(completion: @escaping (String) -> Void) {
    if likesCompletion != nil {
      completion("{\"error\":\"X 点赞请求已在进行中\"}")
      return
    }
    likesCompletion = completion
    likesAttempt = 0
    likesLastPostCount = 0
    likesStalledAttempts = 0
    if likesWebView == nil {
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = dataStore
      let likesWebView = WKWebView(frame: .zero, configuration: configuration)
      likesWebView.navigationDelegate = self
      self.likesWebView = likesWebView
    }
    if likesWindow == nil, let likesWebView {
      let likesWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
      )
      likesWindow.title = "X 点赞列表加载"
      likesWindow.contentView = likesWebView
      likesWindow.orderOut(nil)
      self.likesWindow = likesWindow
    }
    likesWebView?.stopLoading()
    likesWebView?.load(URLRequest(url: URL(string: "https://x.com/i/history/likes")!))
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
    if webView === likesWebView {
      pollLikesPage()
      return
    }
    captureAccountDetails(from: webView, closeWhenDone: false)
  }

  private func pollLikesPage() {
    guard likesCompletion != nil, let likesWebView else { return }
    likesAttempt += 1
    let script = """
      (() => {
        const articles = Array.from(document.querySelectorAll('article[data-testid="tweet"]'));
        const extractMetric = (article, pattern) => {
          const label = Array.from(article.querySelectorAll('button'))
            .map((button) => button.getAttribute('aria-label') || '')
            .find((value) => pattern.test(value));
          return label || null;
        };
        const posts = articles.map((article) => {
          const status = Array.from(article.querySelectorAll('a[href*="/status/"]'))
            .map((link) => link.getAttribute('href') || '')
            .find((href) => /\\/status\\/\\d+/.test(href)) || '';
          const statusParts = status.split('/').filter(Boolean);
          const id = statusParts.length ? statusParts[statusParts.length - 1] : '';
          const authorLink = Array.from(article.querySelectorAll('a[href^="/"]'))
            .map((link) => link.getAttribute('href') || '')
            .find((href) => /^\\/[^/]+$/.test(href));
          const author = authorLink ? '@' + authorLink.slice(1) : '';
          const time = article.querySelector('time');
          const text = article.querySelector('[data-testid="tweetText"]');
          const image = article.querySelector('img[src*="pbs.twimg.com/media"]');
          const video = article.querySelector('video');
          return {
            id,
            author,
            text: text ? text.innerText : '',
            createdAt: time ? time.getAttribute('datetime') : null,
            url: status ? new URL(status, location.origin).toString() : null,
            replies: extractMetric(article, /repl|回复/i),
            reposts: extractMetric(article, /repost|转发/i),
            likes: extractMetric(article, /like|喜欢/i),
            views: extractMetric(article, /view|查看/i),
            mediaUrl: image ? image.getAttribute('src') : (video ? video.getAttribute('poster') : null)
          };
        });
        window.__videoDownloaderLikes = window.__videoDownloaderLikes || {};
        posts.forEach((post) => {
          if (post.id) window.__videoDownloaderLikes[post.id] = post;
        });
        const allPosts = Object.values(window.__videoDownloaderLikes);
        const beforeScroll = window.scrollY;
        window.scrollBy(0, Math.max(window.innerHeight * 0.85, 650));
        return JSON.stringify({
          posts: allPosts.slice(0, \(likesMaxPosts)),
          articleCount: articles.length,
          postCount: allPosts.length,
          atBottom: window.innerHeight + beforeScroll >= document.body.scrollHeight - 200,
          pageUrl: location.href,
          title: document.title,
          readyState: document.readyState,
          bodyText: (document.body ? document.body.innerText : '').slice(0, 800)
        });
      })()
      """
    likesWebView.evaluateJavaScript(script) { [weak self] result, error in
      guard let self else { return }
      if let error {
        self.finishLikes("{\"error\":\"页面读取失败: \(error.localizedDescription)\"}")
        return
      }
      let json = result as? String ?? "{\"posts\":[],\"articleCount\":0,\"postCount\":0}"
      if let data = json.data(using: .utf8),
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let postCount = payload["postCount"] as? Int
      {
        if postCount == self.likesLastPostCount {
          self.likesStalledAttempts += 1
        } else {
          self.likesLastPostCount = postCount
          self.likesStalledAttempts = 0
        }
        let atBottom = payload["atBottom"] as? Bool ?? false
        if postCount >= self.likesMaxPosts ||
          (atBottom && self.likesStalledAttempts >= 3) ||
          self.likesAttempt >= 45
        {
          self.finishLikes(json)
          return
        }
      }
      if self.likesAttempt >= 45 {
        self.finishLikes(json)
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        self?.pollLikesPage()
      }
    }
  }

  private func finishLikes(_ json: String) {
    guard let completion = likesCompletion else { return }
    likesCompletion = nil
    likesWebView?.stopLoading()
    completion(json)
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
