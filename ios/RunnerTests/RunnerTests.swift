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
    try SharedLinkStore.save(source)
    let handoff = try XCTUnwrap(SharedLinkStore.take())
    let components = try XCTUnwrap(URLComponents(url: handoff, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.scheme, "videodownloader")
    XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, source.absoluteString)
    XCTAssertNil(SharedLinkStore.take())
  }

  func testSharedLinkFileOverwritesAndPreservesEncodedQuery() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("pending.txt")
    try SharedLinkStore.save(URL(string: "https://x.com/demo/status/123")!, to: file)
    let latest = try XCTUnwrap(URL(string: "https://x.com/demo/status/456?a=1&text=%E4%B8%AD"))
    try SharedLinkStore.save(latest, to: file)
    let handoff = try XCTUnwrap(SharedLinkStore.take(from: file))
    let components = try XCTUnwrap(URLComponents(url: handoff, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.queryItems?.first(where: { $0.name == "url" })?.value, latest.absoluteString)
    XCTAssertEqual(components.queryItems?.first(where: { $0.name == "source" })?.value, "share_extension")
    XCTAssertNil(try SharedLinkStore.take(from: file))
  }

  func testSharedLinkFileReportsWriteAndInvalidContentErrors() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let missingParent = directory.appendingPathComponent("missing/pending.txt")
    let source = try XCTUnwrap(URL(string: "https://x.com/demo/status/123"))
    XCTAssertThrowsError(try SharedLinkStore.save(source, to: missingParent))
    let invalidFile = directory.appendingPathComponent("invalid.txt")
    try Data("file:///etc/passwd".utf8).write(to: invalidFile)
    XCTAssertThrowsError(try SharedLinkStore.take(from: invalidFile))
    XCTAssertTrue(FileManager.default.fileExists(atPath: invalidFile.path))
  }

  func testShareStorageAndSchemeDeliverOnlyOnceInEitherOrder() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("pending.txt")
    let source = try XCTUnwrap(URL(string: "https://x.com/demo/status/123"))
    for storageFirst in [true, false] {
      let scheme = try SharedLinkStore.save(source, to: file)
      let stored = try XCTUnwrap(SharedLinkStore.take(from: file))
      XCTAssertEqual(scheme, stored)
      var receiver = IncomingShareDeduplicator()
      let deliveries = storageFirst ? [stored, scheme] : [scheme, stored]
      let accepted = try deliveries.map { link in
        let query = try XCTUnwrap(URLComponents(url: link, resolvingAgainstBaseURL: false))
        let requestID = try XCTUnwrap(query.queryItems?.first { $0.name == "request_id" }?.value)
        XCTAssertFalse(requestID.isEmpty)
        return receiver.shouldDeliver(origin: "share_extension", requestID: requestID)
      }
      XCTAssertEqual(accepted, [true, false])
    }
  }

  func testSharingSamePostAgainCreatesNewEvent() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("pending.txt")
    let source = try XCTUnwrap(URL(string: "https://x.com/demo/status/123"))
    var receiver = IncomingShareDeduplicator()
    for _ in 0..<2 {
      let handoff = try SharedLinkStore.save(source, to: file)
      let query = try XCTUnwrap(URLComponents(url: handoff, resolvingAgainstBaseURL: false))
      let requestID = try XCTUnwrap(query.queryItems?.first { $0.name == "request_id" }?.value)
      XCTAssertTrue(receiver.shouldDeliver(origin: "share_extension", requestID: requestID))
      XCTAssertFalse(receiver.shouldDeliver(origin: "share_extension", requestID: requestID))
    }
    XCTAssertTrue(receiver.shouldDeliver(origin: "direct_open", requestID: nil))
    XCTAssertTrue(receiver.shouldDeliver(origin: "share_extension", requestID: nil))
    XCTAssertTrue(receiver.shouldDeliver(origin: "share_extension", requestID: ""))
  }

  func testLegacySharedLinkCanStillBeConsumed() throws {
    let directory = try MediaTestFixtures.directory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("pending.txt")
    let source = "https://x.com/demo/status/123?text=%E4%B8%AD"
    try Data(source.utf8).write(to: file)
    let handoff = try XCTUnwrap(SharedLinkStore.take(from: file))
    let query = try XCTUnwrap(URLComponents(url: handoff, resolvingAgainstBaseURL: false))
    XCTAssertEqual(query.queryItems?.first { $0.name == "url" }?.value, source)
    XCTAssertNil(try SharedLinkStore.take(from: file))
  }

}
