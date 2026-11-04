import Flutter
import UIKit
import XCTest
import AVFoundation
@testable import Runner

class RunnerTests: XCTestCase {

  func testXTokenMatchesJavaScriptNumberConversion() {
    XCTAssertEqual(IosMediaBridge.xToken("1234567890123456789"), "2zqic77uqyk")
    XCTAssertEqual(IosMediaBridge.xToken("705235433198714880"), "1pjk8xy2s3s")
    XCTAssertNil(IosMediaBridge.xToken("123');throw new Error();//"))
  }

  func testMediaPathsStayInsideDocuments() throws {
    let documents = try XCTUnwrap(FileManager.default.urls(
      for: .documentDirectory, in: .userDomainMask
    ).first)
    XCTAssertNotNil(IosMediaBridge.documentURL(documents.appendingPathComponent("video.mp4").path))
    XCTAssertNil(IosMediaBridge.documentURL(documents.appendingPathComponent("../Library/file.mp4").path))
    XCTAssertNil(IosMediaBridge.documentURL("/etc/passwd"))
  }

  func testMergesSeparateVideoAndAudioIntoPlayableMp4() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let video = directory.appendingPathComponent("video.mp4")
    let audio = directory.appendingPathComponent("audio.m4a")
    let output = directory.appendingPathComponent("output.mp4")
    let ready = expectation(description: "video fixture")
    try MediaTestFixtures.video(at: video) { ready.fulfill() }
    wait(for: [ready], timeout: 15)
    try MediaTestFixtures.audio(at: audio)
    let completed = expectation(description: "native merge")
    let merger = IosMediaMerger()
    merger.merge(arguments: [
      "id": UUID().uuidString, "videoPath": video.path,
      "audioPath": audio.path, "outputPath": output.path,
    ]) { result in
      XCTAssertNil(result as? FlutterError)
      let asset = AVURLAsset(url: output)
      XCTAssertEqual(asset.tracks(withMediaType: .video).count, 1)
      XCTAssertEqual(asset.tracks(withMediaType: .audio).count, 1)
      XCTAssertGreaterThan(CMTimeGetSeconds(asset.duration), 0.5)
      completed.fulfill()
    }
    wait(for: [completed], timeout: 30)
  }

  func testRejectsMissingMergeInputs() {
    let done = expectation(description: "invalid input")
    IosMediaMerger().merge(arguments: [:]) { result in
      XCTAssertNotNil(result as? FlutterError)
      done.fulfill()
    }
    wait(for: [done], timeout: 2)
  }

  func testSharedLinkSurvivesUntilHostConsumesItOnce() throws {
    SharedLinkStore.clear()
    defer { SharedLinkStore.clear() }
    let source = try XCTUnwrap(URL(string: "https://x.com/demo/status/123"))
    XCTAssertTrue(SharedLinkStore.save(source))
    let handoff = try XCTUnwrap(SharedLinkStore.take())
    let components = try XCTUnwrap(URLComponents(url: handoff, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "videodownloader")
    XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, source.absoluteString)
    XCTAssertNil(SharedLinkStore.take())
  }

}
