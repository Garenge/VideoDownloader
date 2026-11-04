import AVFoundation
import Flutter

final class IosMediaMerger {
  private var sessions: [String: AVAssetExportSession] = [:]
  private var pending: Set<String> = []
  private var canceled: Set<String> = []

  func cancel(id: String) {
    guard pending.contains(id) else { return }
    canceled.insert(id)
    sessions[id]?.cancelExport()
  }

  func merge(arguments: [String: String]?, result: @escaping FlutterResult) {
    guard let args = arguments, let id = args["id"],
          !pending.contains(id),
          let videoURL = IosMediaBridge.documentURL(args["videoPath"]),
          let audioURL = IosMediaBridge.documentURL(args["audioPath"]),
          let outputURL = IosMediaBridge.documentURL(args["outputPath"]),
          FileManager.default.fileExists(atPath: videoURL.path),
          FileManager.default.fileExists(atPath: audioURL.path),
          !FileManager.default.fileExists(atPath: outputURL.path)
    else {
      result(FlutterError(code: "invalid_merge", message: "合并文件无效或输出文件已存在", details: nil))
      return
    }
    pending.insert(id)
    let video = AVURLAsset(url: videoURL)
    let audio = AVURLAsset(url: audioURL)
    video.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
      audio.loadValuesAsynchronously(forKeys: ["tracks", "duration"]) {
        DispatchQueue.main.async {
          self.start(id: id, video: video, audio: audio, output: outputURL, result: result)
        }
      }
    }
  }

  private func start(
    id: String, video: AVAsset, audio: AVAsset, output: URL,
    result: @escaping FlutterResult
  ) {
    do {
      if canceled.contains(id) { throw NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled) }
      let composition = try compose(video: video, audio: audio)
      guard let session = AVAssetExportSession(
        asset: composition, presetName: AVAssetExportPresetHighestQuality
      ) else { throw NSError(domain: "VideoDownloader.Merge", code: 1) }
      sessions[id] = session
      session.outputURL = output
      session.outputFileType = .mp4
      session.shouldOptimizeForNetworkUse = true
      session.exportAsynchronously {
        DispatchQueue.main.async {
          let error = session.status == .completed ? nil : session.error ??
            NSError(domain: "VideoDownloader.Merge", code: 2)
          self.finish(id: id, output: output, error: error, result: result)
        }
      }
    } catch {
      finish(id: id, output: output, error: error, result: result)
    }
  }

  private func compose(video: AVAsset, audio: AVAsset) throws -> AVMutableComposition {
    let composition = AVMutableComposition()
    guard let sourceVideo = video.tracks(withMediaType: .video).first,
          let sourceAudio = audio.tracks(withMediaType: .audio).first,
          let targetVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
          ),
          let targetAudio = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
          )
    else { throw NSError(domain: "VideoDownloader.MissingTracks", code: 1) }
    try targetVideo.insertTimeRange(
      CMTimeRange(start: .zero, duration: video.duration), of: sourceVideo, at: .zero
    )
    targetVideo.preferredTransform = sourceVideo.preferredTransform
    try targetAudio.insertTimeRange(
      CMTimeRange(start: .zero, duration: CMTimeMinimum(video.duration, audio.duration)),
      of: sourceAudio, at: .zero
    )
    return composition
  }

  private func finish(id: String, output: URL, error: Error?, result: @escaping FlutterResult) {
    sessions.removeValue(forKey: id)
    pending.remove(id)
    canceled.remove(id)
    if let error {
      try? FileManager.default.removeItem(at: output)
      print("ios/Runner/IosMediaMerger.swift#finish: merge failed id=\(id) error=\(error.localizedDescription)")
      result(FlutterError(code: "merge_failed", message: "音视频合并失败：\(error.localizedDescription)", details: nil))
    } else {
      result(nil)
    }
  }
}
