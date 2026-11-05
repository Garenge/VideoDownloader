import Foundation

/// Runner 与 Share Extension 通过 App Group 中的原子文件交接链接。
enum SharedLinkStore {
  private struct PendingShare: Codable {
    let url: URL
    let requestID: String
  }

  enum StorageError: LocalizedError {
    case missingGroup
    case unavailableContainer(String)
    case invalidLink

    var errorDescription: String? {
      switch self {
      case .missingGroup: return "未配置 VideoDownloaderAppGroup"
      case .unavailableContainer(let group): return "无法访问共享容器：\(group)"
      case .invalidLink: return "共享存储中的链接格式无效"
      }
    }
  }

  private static func pendingFile() throws -> URL {
    guard let group = Bundle.main.object(
      forInfoDictionaryKey: "VideoDownloaderAppGroup"
    ) as? String, !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { throw StorageError.missingGroup }
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: group
    ) else { throw StorageError.unavailableContainer(group) }
    return container.appendingPathComponent("pending_shared_url.txt")
  }

  @discardableResult
  static func save(_ url: URL) throws -> URL {
    let handoff = try save(url, to: pendingFile())
    print("ios/Runner/SharedLinkStore.swift#save: shared link saved")
    return handoff
  }

  @discardableResult
  static func save(_ url: URL, to file: URL) throws -> URL {
    let share = PendingShare(url: url, requestID: UUID().uuidString)
    let handoff = try handoffURL(share)
    try JSONEncoder().encode(share).write(to: file, options: .atomic)
    return handoff
  }

  static func take() -> URL? {
    do {
      return try take(from: pendingFile())
    } catch {
      print("ios/Runner/SharedLinkStore.swift#take: failed error=\(error)")
      return nil
    }
  }

  static func take(from file: URL) throws -> URL? {
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let data = try Data(contentsOf: file)
    let share: PendingShare
    if let stored = try? JSONDecoder().decode(PendingShare.self, from: data) {
      share = stored
    } else if let text = String(data: data, encoding: .utf8), let url = URL(string: text) {
      share = PendingShare(url: url, requestID: UUID().uuidString)
    } else {
      throw StorageError.invalidLink
    }
    let handoff = try handoffURL(share)
    try FileManager.default.removeItem(at: file)
    return handoff
  }

  private static func handoffURL(_ share: PendingShare) throws -> URL {
    guard ["http", "https"].contains(share.url.scheme?.lowercased() ?? ""),
          let host = share.url.host, !host.isEmpty
    else { throw StorageError.invalidLink }
    var components = URLComponents()
    components.scheme = "videodownloader"
    components.host = "parse"
    components.queryItems = [
      URLQueryItem(name: "url", value: share.url.absoluteString),
      URLQueryItem(name: "source", value: "share_extension"),
      URLQueryItem(name: "request_id", value: share.requestID),
      URLQueryItem(name: "match", value: "x_status"),
    ]
    guard let handoff = components.url else { throw StorageError.invalidLink }
    return handoff
  }

  static func clear() {
    do {
      let file = try pendingFile()
      if FileManager.default.fileExists(atPath: file.path) {
        try FileManager.default.removeItem(at: file)
      }
    } catch {
      print("ios/Runner/SharedLinkStore.swift#clear: failed error=\(error)")
    }
  }
}

/// 只按分享事件去重，同一个帖子的新分享仍会被接收。
struct IncomingShareDeduplicator {
  private var handledIDs = Set<String>()

  mutating func shouldDeliver(origin: String, requestID: String?) -> Bool {
    guard origin == "share_extension", let requestID, !requestID.isEmpty else { return true }
    return handledIDs.insert(requestID).inserted
  }
}
