import Cocoa
import WebKit

final class XLikesController: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
  private var webView: WKWebView?
  private var window: NSWindow?
  private var completion: ((String) -> Void)?
  private var timeout: DispatchWorkItem?
  private var requestID = UUID()

  func fetch(cursor: String?, completion: @escaping (String) -> Void) {
    guard self.completion == nil else {
      completion(Self.json(["error": "X 点赞请求已在进行中"]))
      return
    }
    requestID = UUID()
    let currentID = requestID
    self.completion = completion
    let task = DispatchWorkItem { [weak self] in
      guard let self, self.requestID == currentID else { return }
      self.finish(["error": "X 点赞请求超时，请确认应用内已登录并检查网络"], reset: true)
    }
    timeout = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: task)
    if let cursor {
      loadNext(cursor)
    } else {
      resetWebView()
      checkLoginAndLoad(currentID)
    }
  }

  private func checkLoginAndLoad(_ currentID: UUID) {
    WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
      guard let self, self.completion != nil, self.requestID == currentID else { return }
      let authenticated = cookies.contains {
        let domain = $0.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return $0.name == "auth_token" && (domain == "x.com" || domain.hasSuffix(".x.com"))
      }
      guard authenticated else {
        self.finish(["error": "请先在设置中登录 X，再刷新点赞列表"])
        return
      }
      self.createWebView()
    }
  }

  private func createWebView() {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .default()
    configuration.userContentController.add(self, name: "xLikes")
    configuration.userContentController.addUserScript(WKUserScript(
      source: XLikesScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
    view.navigationDelegate = self
    let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    self.window = window
    webView = view
    view.load(URLRequest(url: URL(string: "https://x.com/i/history/likes")!))
  }

  private func loadNext(_ cursor: String) {
    guard let webView else {
      finish(["error": "点赞会话已结束，请刷新列表"], reset: true)
      return
    }
    let currentID = requestID
    let argument = Self.json(["cursor": cursor])
    webView.evaluateJavaScript("window.__videoDownloaderNextLikes(\(argument).cursor); void 0") {
      [weak self] _, error in
      guard let self, self.requestID == currentID else { return }
      if error != nil {
        self.finish(["error": "X 点赞分页读取失败，请刷新列表"], reset: true)
      }
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard message.webView === webView, message.frameInfo.isMainFrame,
      message.frameInfo.securityOrigin.host == "x.com",
      let payload = message.body as? [String: Any] else { return }
    finish(payload)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard webView === self.webView else { return }
    if webView.url?.path.contains("/login") == true {
      finish(["error": "X 登录已失效，请在设置中重新登录"], reset: true)
    }
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    guard webView === self.webView else { return }
    finish(["error": "X 点赞页面加载失败，请检查网络后重试"], reset: true)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    guard webView === self.webView else { return }
    finish(["error": "X 点赞页面加载失败，请重试"], reset: true)
  }

  func cancel() {
    finish(["error": "X 点赞请求已取消"], reset: true)
  }

  private func finish(_ payload: [String: Any], reset: Bool = false) {
    timeout?.cancel()
    timeout = nil
    let callback = completion
    completion = nil
    if reset { resetWebView() }
    var response = payload
    if reset { response["requiresRefresh"] = true }
    callback?(Self.json(response))
  }

  private func resetWebView() {
    webView?.configuration.userContentController.removeScriptMessageHandler(forName: "xLikes")
    webView?.stopLoading()
    webView = nil
    window?.close()
    window = nil
  }

  private static func json(_ value: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: value),
      let text = String(data: data, encoding: .utf8) else { return "{}" }
    return text
  }
}
