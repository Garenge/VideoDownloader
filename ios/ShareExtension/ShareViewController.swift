import Foundation
import UIKit

private enum SharedUrlExtractionResult: Equatable {
  case success(URL)
  case unsupportedWebLink
  case missing
}

final class ShareViewController: UIViewController {
  private let _statusLabel = UILabel()
  private let _detailLabel = UILabel()
  private let _dismissButton = UIButton(type: .system)
  private var _hasStartedProcessing = false

  override func viewDidLoad() {
    super.viewDidLoad()
    _buildLoadingView()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !_hasStartedProcessing else {
      return
    }

    _hasStartedProcessing = true
    _startShareFlow()
  }

  private func _buildLoadingView() {
    view.backgroundColor = .systemBackground

    _statusLabel.translatesAutoresizingMaskIntoConstraints = false
    _statusLabel.numberOfLines = 0
    _statusLabel.textAlignment = .center
    _statusLabel.font = .preferredFont(forTextStyle: .body)
    _statusLabel.textColor = .label
    _statusLabel.text = "正在发送链接到 VideoDownloader..."
    view.addSubview(_statusLabel)

    _detailLabel.translatesAutoresizingMaskIntoConstraints = false
    _detailLabel.numberOfLines = 0
    _detailLabel.textAlignment = .center
    _detailLabel.font = .preferredFont(forTextStyle: .footnote)
    _detailLabel.textColor = .secondaryLabel
    _detailLabel.text = "当前只支持 X / Twitter 帖子链接，并会交给主 App 自动解析"
    view.addSubview(_detailLabel)

    _dismissButton.translatesAutoresizingMaskIntoConstraints = false
    _dismissButton.setTitle("关闭", for: .normal)
    _dismissButton.setTitleColor(view.tintColor, for: .normal)
    _dismissButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
    _dismissButton.layer.cornerRadius = 10
    _dismissButton.layer.borderWidth = 1
    _dismissButton.layer.borderColor = view.tintColor.cgColor
    _dismissButton.isHidden = true
    _dismissButton.addTarget(self, action: #selector(_handleDismissTapped), for: .touchUpInside)
    view.addSubview(_dismissButton)

    NSLayoutConstraint.activate([
      _statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      _statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -28),
      _statusLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.leadingAnchor,
        constant: 24
      ),
      _statusLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -24
      ),
      _detailLabel.topAnchor.constraint(equalTo: _statusLabel.bottomAnchor, constant: 12),
      _detailLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      _detailLabel.leadingAnchor.constraint(
        greaterThanOrEqualTo: view.leadingAnchor,
        constant: 24
      ),
      _detailLabel.trailingAnchor.constraint(
        lessThanOrEqualTo: view.trailingAnchor,
        constant: -24
      ),
      _dismissButton.topAnchor.constraint(equalTo: _detailLabel.bottomAnchor, constant: 18),
      _dismissButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
    ])
  }

  @objc
  private func _handleDismissTapped() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }

  private func _startShareFlow() {
    _extractSharedUrl { [weak self] result in
      guard let self else {
        return
      }

      let sharedUrl: URL
      switch result {
      case let .success(url):
        sharedUrl = url
      case .unsupportedWebLink:
        self._finishWithError("当前分享扩展仅支持 X 帖子链接，请从 X 帖子详情页重新分享")
        return
      case .missing:
        self._finishWithError("没有从分享内容中找到可用的 X 帖子链接")
        return
      }

      print(
        "ios/ShareExtension/ShareViewController.swift#_startShareFlow: sharedUrl=\(sharedUrl.absoluteString)"
      )
      guard let appUrl = self._saveSharedUrl(sharedUrl) else { return }
      self._openHostApp(appUrl)
    }
  }

  private func _saveSharedUrl(_ url: URL) -> URL? {
    do {
      return try SharedLinkStore.save(url)
    } catch {
      let storageError = error as? SharedLinkStore.StorageError
      let title = storageError == nil ? "分享链接写入失败" : "分享存储未就绪"
      print(
        "ios/ShareExtension/ShareViewController.swift#_saveSharedUrl: failed error=\(error)"
      )
      _finishWithError(title, detail: error.localizedDescription)
      return nil
    }
  }

  private func _openHostApp(_ appUrl: URL) {
    ShareHostAppOpener.open(appUrl, from: self) { success in
      DispatchQueue.main.async {
        if success {
          print(
            "ios/ShareExtension/ShareViewController.swift#_openHostApp: opened host app url=\(appUrl.absoluteString)"
          )
          self.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
          return
        }
        print(
          "ios/ShareExtension/ShareViewController.swift#_openHostApp: open failed, shared link remains saved"
        )
        self._statusLabel.text = "链接已保存"
        self._detailLabel.text = "关闭此窗口后打开 VideoDownloader，App 会自动接收并解析链接"
        self._dismissButton.isHidden = false
      }
    }
  }

  private func _extractSharedUrl(
    completion: @escaping (SharedUrlExtractionResult) -> Void
  ) {
    let extensionItems = extensionContext?.inputItems.compactMap {
      $0 as? NSExtensionItem
    } ?? []

    let attributedTextResult = _extractPreferredSharedUrlFromAttributedText(extensionItems)
    switch attributedTextResult {
    case let .success(url):
      completion(.success(url))
      return
    case .unsupportedWebLink, .missing:
      break
    }

    let providers = extensionItems.flatMap { item in
      item.attachments ?? []
    }
    _extractSharedUrl(
      from: providers,
      index: 0,
      sawUnsupportedWebLink: attributedTextResult == .unsupportedWebLink,
      completion: completion
    )
  }

  private func _extractSharedUrl(
    from providers: [NSItemProvider],
    index: Int,
    sawUnsupportedWebLink: Bool,
    completion: @escaping (SharedUrlExtractionResult) -> Void
  ) {
    if index >= providers.count {
      completion(sawUnsupportedWebLink ? .unsupportedWebLink : .missing)
      return
    }

    let provider = providers[index]
    if provider.hasItemConformingToTypeIdentifier("public.url") {
      provider.loadItem(forTypeIdentifier: "public.url", options: nil) {
        [weak self] item, error in
        self?._handleLoadedProviderItem(
          item,
          error: error,
          providers: providers,
          index: index,
          sawUnsupportedWebLink: sawUnsupportedWebLink,
          completion: completion
        )
      }
      return
    }

    if provider.hasItemConformingToTypeIdentifier("public.plain-text") ||
      provider.hasItemConformingToTypeIdentifier("public.text") {
      let typeIdentifier = provider.hasItemConformingToTypeIdentifier("public.plain-text")
        ? "public.plain-text"
        : "public.text"
      provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) {
        [weak self] item, error in
        self?._handleLoadedProviderItem(
          item,
          error: error,
          providers: providers,
          index: index,
          sawUnsupportedWebLink: sawUnsupportedWebLink,
          completion: completion
        )
      }
      return
    }

    _extractSharedUrl(
      from: providers,
      index: index + 1,
      sawUnsupportedWebLink: sawUnsupportedWebLink,
      completion: completion
    )
  }

  private func _handleLoadedProviderItem(
    _ item: NSSecureCoding?,
    error: Error?,
    providers: [NSItemProvider],
    index: Int,
    sawUnsupportedWebLink: Bool,
    completion: @escaping (SharedUrlExtractionResult) -> Void
  ) {
    if let error {
      print(
        "ios/ShareExtension/ShareViewController.swift#_handleLoadedProviderItem: failed index=\(index) error=\(error.localizedDescription)"
      )
    }

    let result = _extractResult(from: item)

    DispatchQueue.main.async {
      switch result {
      case let .success(sharedUrl):
        completion(.success(sharedUrl))
        return
      case .unsupportedWebLink, .missing:
        break
      }

      self._extractSharedUrl(
        from: providers,
        index: index + 1,
        sawUnsupportedWebLink: sawUnsupportedWebLink || result == .unsupportedWebLink,
        completion: completion
      )
    }
  }

  private func _extractPreferredSharedUrlFromAttributedText(
    _ items: [NSExtensionItem]
  ) -> SharedUrlExtractionResult {
    var sawUnsupportedWebLink = false
    for item in items {
      let result = _extractResult(from: item.attributedContentText?.string)
      switch result {
      case let .success(url):
        return .success(url)
      case .unsupportedWebLink:
        sawUnsupportedWebLink = true
      case .missing:
        break
      }
    }
    return sawUnsupportedWebLink ? .unsupportedWebLink : .missing
  }

  private func _extractResult(from item: NSSecureCoding?) -> SharedUrlExtractionResult {
    if let url = item as? URL {
      return _extractResult(from: url)
    }
    if let text = item as? String {
      return _extractResult(from: text)
    }
    if let attributedText = item as? NSAttributedString {
      return _extractResult(from: attributedText.string)
    }
    return .missing
  }

  private func _extractResult(from url: URL) -> SharedUrlExtractionResult {
    if _isSupportedXStatusUrl(url) {
      return .success(url)
    }
    if _isHttpUrl(url) {
      return .unsupportedWebLink
    }
    return .missing
  }

  private func _extractResult(from text: String?) -> SharedUrlExtractionResult {
    guard let text, !text.isEmpty else {
      return .missing
    }

    let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    )
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = detector?.matches(in: text, options: [], range: range) ?? []
    var sawUnsupportedWebLink = false
    for match in matches {
      guard let url = match.url else {
        continue
      }
      if !_isHttpUrl(url) {
        continue
      }
      if _isSupportedXStatusUrl(url) {
        return .success(url)
      }
      sawUnsupportedWebLink = true
    }
    return sawUnsupportedWebLink ? .unsupportedWebLink : .missing
  }

  private func _isHttpUrl(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else {
      return false
    }
    return scheme == "http" || scheme == "https"
  }

  private func _isSupportedXStatusUrl(_ url: URL) -> Bool {
    let host = url.host?.lowercased() ?? ""
    let isXHost =
      host == "x.com" || host == "www.x.com" ||
      host == "twitter.com" || host == "www.twitter.com" ||
      host == "mobile.twitter.com" ||
      host.hasSuffix(".x.com") || host.hasSuffix(".twitter.com")
    if !isXHost {
      return false
    }

    let segments = url.path.split(separator: "/")
    if segments.count < 3 {
      return false
    }
    if segments[1].lowercased() != "status" {
      return false
    }
    return segments[2].allSatisfy(\.isNumber)
  }

  private func _finishWithError(
    _ message: String,
    detail: String = "请返回分享页重试，或先确认分享内容里是否真的带有网页链接。"
  ) {
    print("ios/ShareExtension/ShareViewController.swift#_finishWithError: \(message)")
    _statusLabel.text = message
    _detailLabel.text = detail
    _dismissButton.isHidden = false
  }
}
