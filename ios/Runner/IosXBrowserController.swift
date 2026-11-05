import Flutter
import UIKit
import WebKit

final class IosXBrowserController: UIViewController, WKNavigationDelegate,
  WKHTTPCookieStoreObserver, WKScriptMessageHandler, UIAdaptivePresentationControllerDelegate
{
  private let session: IosXSession
  private let statusID: String?
  private var completion: FlutterResult?
  private var webView: WKWebView!
  private var timeout: Timer?
  private let message = UILabel()
  private let target: URL
  private var receivedTweet = false
  private var pageLoaded = false
  private var loadStartedAt = Date()

  init(session: IosXSession, target: URL, statusID: String?, completion: @escaping FlutterResult) {
    self.session = session
    self.target = target
    self.statusID = statusID
    self.completion = completion
    super.init(nibName: nil, bundle: nil)
    isModalInPresentation = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    title = statusID == nil ? "登录 X" : "读取 X 图片和视频"
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "关闭", style: .plain, target: self, action: #selector(close)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "重试", style: .plain, target: self, action: #selector(retry)
    )
    configureWebView()
    session.store.httpCookieStore.add(self)
    loadPage(cachePolicy: .useProtocolCachePolicy)
  }

  private func configureWebView() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = session.store
    // X redirects the default embedded-browser agent to x-safari-https before loading the page.
    config.applicationNameForUserAgent =
      "Version/\(UIDevice.current.systemVersion) Mobile/15E148 Safari/604.1"
    if let statusID {
      config.userContentController.add(self, name: "xMedia")
      config.userContentController.addUserScript(WKUserScript(
        source: IosXMediaScript.source(statusID: statusID),
        injectionTime: .atDocumentStart, forMainFrameOnly: true
      ))
    }
    webView = WKWebView(frame: .zero, configuration: config)
    webView.navigationDelegate = self
    message.numberOfLines = 0
    message.font = .preferredFont(forTextStyle: .footnote)
    message.textColor = .secondaryLabel
    let stack = UIStackView(arrangedSubviews: [message, webView])
    stack.axis = .vertical
    stack.spacing = 8
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
    ])
  }

  @objc private func retry() {
    loadPage(cachePolicy: .reloadIgnoringLocalCacheData)
  }

  private func loadPage(cachePolicy: URLRequest.CachePolicy) {
    loadStartedAt = Date()
    receivedTweet = false
    pageLoaded = false
    message.text = statusID == nil
      ? "请在 X 官方网页完成登录，登录成功后自动返回。登录状态仅保存在本机。"
      : "正在加载帖子网页，使用本机 X 登录状态…"
    logLoadPhase("load_started")
    webView.load(URLRequest(url: target, cachePolicy: cachePolicy))
    startTimeout()
  }

  private func startTimeout() {
    timeout?.invalidate()
    timeout = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
      guard let self else { return }
      if self.statusID != nil {
        self.finish(FlutterError(
          code: "x_media_unavailable",
          message: self.receivedTweet
            ? "已收到帖子数据，但未找到可下载的图片或 MP4；帖子可能限制访问或没有可用媒体。"
            : self.pageLoaded
              ? "帖子网页已加载，但未收到目标媒体数据，请确认网页是否显示该帖子。"
              : "帖子网页未完成加载，请重试。",
          details: nil
        ))
      } else if self.webView.isLoading {
        self.message.text = "X 登录网页加载较慢，请检查网络或代理，然后点击重试。"
      }
    }
  }

  @objc private func close() {
    if statusID != nil {
      finish(FlutterError(code: "canceled", message: "已取消读取 X 图片和视频", details: nil))
    } else {
      session.status { [weak self] status in self?.finish(status["authenticated"] as? Bool ?? false) }
    }
  }

  func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
    guard statusID == nil else { return }
    session.status { [weak self] status in
      if status["authenticated"] as? Bool == true { self?.finish(true) }
    }
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    guard let host = message.frameInfo.securityOrigin.host as String?,
          IosXSession.isXDomain(host),
          let body = message.body as? [String: Any]
    else { return }
    if let phase = body["phase"] as? String { updateMediaPhase(phase) }
    guard let urls = body["urls"] as? [String] else { return }
    var seen = Set<String>()
    let valid = urls.filter { Self.isMediaURL($0) && seen.insert($0).inserted }
    if !valid.isEmpty { finish(valid) }
  }

  static func isMediaURL(_ value: String) -> Bool {
    guard let url = URL(string: value), let host = url.host,
          url.scheme == "https", url.user == nil, url.password == nil
    else { return false }
    if host == "pbs.twimg.com" { return url.path.hasPrefix("/media/") }
    return (host == "video.twimg.com" || host.hasSuffix(".video.twimg.com"))
      && url.path.lowercased().hasSuffix(".mp4")
  }

  private func updateMediaPhase(_ phase: String) {
    logLoadPhase(phase)
    if phase == "observer_ready" {
      message.text = "已启动图片和视频提取，正在等待帖子数据…"
    } else if phase == "tweet_received" {
      receivedTweet = true
      message.text = "已收到帖子数据，正在提取图片和视频地址…"
    }
  }

  private func logLoadPhase(_ phase: String) {
    let elapsed = Int(Date().timeIntervalSince(loadStartedAt) * 1000)
    print("ios/Runner/IosXBrowserController.swift#logLoadPhase: phase=\(phase) elapsedMs=\(elapsed)")
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme
    let url = navigationAction.request.url
    print("ios/Runner/IosXBrowserController.swift#decidePolicyFor: scheme=\(scheme ?? "") host=\(url?.host ?? "") path=\(url?.path ?? "")")
    decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    pageLoaded = true
    logLoadPhase("page_loaded")
    print("ios/Runner/IosXBrowserController.swift#didFinish: receivedTweet=\(receivedTweet)")
    if statusID != nil && !receivedTweet {
      message.text = "帖子网页已加载，正在等待媒体数据；可在下方确认帖子内容。"
    }
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    handleNavigationError(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    handleNavigationError(error)
  }

  private func handleNavigationError(_ error: Error) {
    let failure = error as NSError
    let interrupted = Self.isNavigationInterruption(failure)
    print("ios/Runner/IosXBrowserController.swift#handleNavigationError: domain=\(failure.domain) code=\(failure.code) interrupted=\(interrupted)")
    guard !interrupted else { return }
    if statusID != nil {
      finish(FlutterError(
        code: "x_network",
        message: "X 网页加载失败：\(failure.localizedDescription)",
        details: ["domain": failure.domain, "code": failure.code]
      ))
    } else {
      message.text = "X 登录网页加载失败，请检查网络或代理，然后点击重试。"
    }
  }

  static func isNavigationInterruption(_ error: NSError) -> Bool {
    // Canceling an app deep link can interrupt navigation without a network failure.
    return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
      || (error.domain == "WebKitErrorDomain" && error.code == 102)
  }

  private func finish(_ value: Any) {
    guard let callback = completion else { return }
    logLoadPhase(value is FlutterError ? "failed_or_canceled" : "completed")
    completion = nil
    timeout?.invalidate()
    timeout = nil
    webView.stopLoading()
    webView.navigationDelegate = nil
    session.store.httpCookieStore.remove(self)
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "xMedia")
    dismiss(animated: true) { callback(value) }
  }
}
