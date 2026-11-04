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
    title = statusID == nil ? "登录 X" : "读取 X 视频"
    view.backgroundColor = .systemBackground
    navigationItem.leftBarButtonItem = UIBarButtonItem(
      title: "关闭", style: .plain, target: self, action: #selector(close)
    )
    navigationItem.rightBarButtonItem = UIBarButtonItem(
      title: "重试", style: .plain, target: self, action: #selector(retry)
    )
    configureWebView()
    session.store.httpCookieStore.add(self)
    retry()
  }

  private func configureWebView() {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = session.store
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
    message.text = statusID == nil
      ? "请在 X 官方网页完成登录，登录成功后自动返回。登录状态仅保存在本机。"
      : "正在使用本机 X 登录状态读取此帖子；关闭可取消。"
    webView.load(URLRequest(url: target))
    startTimeout()
  }

  private func startTimeout() {
    timeout?.invalidate()
    timeout = Timer.scheduledTimer(withTimeInterval: 40, repeats: false) { [weak self] _ in
      guard let self else { return }
      if self.statusID != nil {
        self.finish(FlutterError(
          code: "x_media_unavailable",
          message: "未能读取此帖子的 MP4，请检查网络、登录状态或帖子访问权限", details: nil
        ))
      } else if self.webView.isLoading {
        self.message.text = "X 登录网页加载较慢，请检查网络或代理，然后点击重试。"
      }
    }
  }

  @objc private func close() {
    if statusID != nil {
      finish(FlutterError(code: "canceled", message: "已取消读取 X 视频", details: nil))
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
          let body = message.body as? [String: Any], let urls = body["urls"] as? [String]
    else { return }
    let valid = urls.filter { value in
      guard let url = URL(string: value), let host = url.host else { return false }
      return url.scheme == "https" &&
        (host == "video.twimg.com" || host.hasSuffix(".video.twimg.com"))
    }
    if !valid.isEmpty { finish(Array(Set(valid)).sorted()) }
  }

  func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
               decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    let scheme = navigationAction.request.url?.scheme
    decisionHandler(scheme == "https" || scheme == "about" ? .allow : .cancel)
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
               withError error: Error) {
    handleNavigationError(error)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    handleNavigationError(error)
  }

  private func handleNavigationError(_ error: Error) {
    guard (error as NSError).code != NSURLErrorCancelled else { return }
    print("ios/Runner/IosXBrowserController.swift#handleNavigationError: code=\((error as NSError).code)")
    if statusID != nil {
      finish(FlutterError(code: "x_network", message: "X 网页加载失败，请检查网络或代理", details: nil))
    } else {
      message.text = "X 登录网页加载失败，请检查网络或代理，然后点击重试。"
    }
  }

  private func finish(_ value: Any) {
    guard let callback = completion else { return }
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
