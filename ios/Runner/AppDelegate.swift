import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private static let incomingLinkChannelName = "videodownloader/incoming_link"
  private static var incomingLinkChannel: FlutterMethodChannel?
  private static var pendingIncomingLinkPayload: [String: Any]?
  private static var incomingLinkDartReady = false
  private static var shareDeduplicator = IncomingShareDeduplicator()
  private let mediaBridge = IosMediaBridge()
  private let xLoginBridge = IosXLoginBridge()
  private let backgroundKeepAlive = IosBackgroundKeepAlive()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if Self.handleIncomingUrl(url, source: "application_open_url") {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    mediaBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    xLoginBridge.register(messenger: engineBridge.applicationRegistrar.messenger())
    backgroundKeepAlive.register(messenger: engineBridge.applicationRegistrar.messenger())
    let channel = FlutterMethodChannel(
      name: Self.incomingLinkChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getInitialLink":
        Self.incomingLinkDartReady = true
        if Self.pendingIncomingLinkPayload == nil, let shared = SharedLinkStore.take() {
          let payload = Self.extractIncomingPayload(
            from: shared, source: "shared_storage_initial"
          )
          if let payload, Self.shouldDeliver(payload) {
            Self.pendingIncomingLinkPayload = payload
          }
        }
        let pendingPayload = Self.pendingIncomingLinkPayload
        Self.pendingIncomingLinkPayload = nil
        print(
          "ios/Runner/AppDelegate.swift#getInitialLink: pendingPayload=\(String(describing: pendingPayload))"
        )
        result(pendingPayload)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    Self.incomingLinkChannel = channel
    print("ios/Runner/AppDelegate.swift#didInitializeImplicitFlutterEngine: channel ready")
  }

  static func handleIncomingUrl(_ url: URL, source: String) -> Bool {
    guard let payload = extractIncomingPayload(from: url, source: source) else {
      print(
        "ios/Runner/AppDelegate.swift#handleIncomingUrl: ignored source=\(source) rawUrl=\(url.absoluteString)"
      )
      return false
    }

    let incomingUrl = payload["url"] as? String ?? "nil"
    let origin = payload["origin"] as? String ?? "unknown"
    if origin == "share_extension" { SharedLinkStore.clear() }
    guard shouldDeliver(payload) else { return true }
    print(
      "ios/Runner/AppDelegate.swift#handleIncomingUrl: source=\(source) origin=\(origin) incomingUrl=\(incomingUrl)"
    )

    guard let channel = incomingLinkChannel, incomingLinkDartReady else {
      pendingIncomingLinkPayload = payload
      print(
        "ios/Runner/AppDelegate.swift#handleIncomingUrl: channel not ready, cached incomingUrl=\(incomingUrl)"
      )
      return true
    }

    channel.invokeMethod("onIncomingLink", arguments: payload)
    return true
  }

  static func consumeSharedLink() {
    if let url = SharedLinkStore.take() {
      _ = handleIncomingUrl(url, source: "shared_storage_resume")
    }
  }

  private static func shouldDeliver(_ payload: [String: Any]) -> Bool {
    let accepted = shareDeduplicator.shouldDeliver(
      origin: payload["origin"] as? String ?? "",
      requestID: payload["requestID"] as? String
    )
    if !accepted {
      print("ios/Runner/AppDelegate.swift#shouldDeliver: ignored duplicate share event")
    }
    return accepted
  }

  private static func extractIncomingPayload(
    from url: URL,
    source: String
  ) -> [String: Any]? {
    let scheme = url.scheme?.lowercased()
    if scheme == "http" || scheme == "https" {
      let resolvedUrl = url.absoluteString
      let debugLog = [
        "[Incoming Link Native Log]",
        "entrySource=\(source)",
        "origin=direct_open",
        "rawUrl=\(url.absoluteString)",
        "resolvedUrl=\(resolvedUrl)",
      ].joined(separator: "\n")
      return [
        "url": resolvedUrl,
        "origin": "direct_open",
        "debugLog": debugLog,
      ]
    }

    guard scheme == "videodownloader",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems
    else {
      return nil
    }

    let rawTarget = queryItems.first { item in
      item.name == "url" || item.name == "link"
    }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let rawTarget,
          let targetUrl = URL(string: rawTarget),
          let targetScheme = targetUrl.scheme?.lowercased(),
          targetScheme == "http" || targetScheme == "https"
    else {
      return nil
    }

    let origin = queryItems.first { item in
      item.name == "source"
    }?.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "custom_scheme"
    let matchType = queryItems.first { item in
      item.name == "match"
    }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
    let requestID = queryItems.first { $0.name == "request_id" }?.value ?? ""

    var debugLogLines = [
      "[Incoming Link Native Log]",
      "entrySource=\(source)",
      "origin=\(origin)",
      "rawUrl=\(url.absoluteString)",
      "resolvedUrl=\(targetUrl.absoluteString)",
      "requestID=\(requestID)",
    ]
    if let matchType, !matchType.isEmpty {
      debugLogLines.append("match=\(matchType)")
    }
    let debugLog = debugLogLines.joined(separator: "\n")

    return [
      "url": targetUrl.absoluteString,
      "origin": origin,
      "requestID": requestID,
      "debugLog": debugLog,
    ]
  }
}
