import AVFoundation
import XCTest

enum MediaTestFixtures {
  static func directory() throws -> URL {
    let documents = try XCTUnwrap(FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first)
    let directory = documents.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  static func audio(at url: URL) throws {
    let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
    let file = try AVAudioFile(forWriting: url, settings: [
      AVFormatIDKey: kAudioFormatMPEG4AAC,
      AVSampleRateKey: 44100,
      AVNumberOfChannelsKey: 1,
      AVEncoderBitRateKey: 64000,
    ])
    let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100))
    buffer.frameLength = 44100
    memset(buffer.floatChannelData![0], 0, 44100 * MemoryLayout<Float>.size)
    try file.write(from: buffer)
  }

  static func video(at url: URL, completion: @escaping () -> Void) throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 64,
      AVVideoHeightKey: 64,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
      assetWriterInput: input,
      sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 64,
        kCVPixelBufferHeightKey as String: 64,
      ]
    )
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    var frame: Int64 = 0
    input.requestMediaDataWhenReady(on: DispatchQueue(label: "video.fixture")) {
      while input.isReadyForMoreMediaData && frame < 30 {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
          XCTFail("Cannot allocate fixture frame")
          input.markAsFinished()
          writer.cancelWriting()
          completion()
          return
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        guard adaptor.append(buffer, withPresentationTime: CMTime(value: frame, timescale: 30)) else {
          XCTFail("Cannot append fixture frame")
          writer.cancelWriting()
          completion()
          return
        }
        frame += 1
      }
      if frame == 30 {
        input.markAsFinished()
        writer.finishWriting(completionHandler: completion)
      }
    }
  }
}
