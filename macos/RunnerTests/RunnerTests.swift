import Cocoa
import FlutterMacOS
import XCTest
@testable import videodownloader

@MainActor
class RunnerTests: XCTestCase {

  func testRepeatedLoginWindowClose() throws {
    let controller = XLoginWindowController()
    let completed = expectation(description: "Each closed login completes once")
    completed.expectedFulfillmentCount = 10
    for _ in 0..<10 {
      try autoreleasepool {
        controller.openLogin { _ in completed.fulfill() }
        let window = try loginWindow()
        XCTAssertFalse(window.isReleasedWhenClosed)
        window.close()
      }
    }
    wait(for: [completed], timeout: 10)
  }

  func testClosingOldLoginDoesNotClearReopenedWindow() throws {
    let controller = XLoginWindowController()
    let firstClosed = expectation(description: "First login closes")
    let secondClosed = expectation(description: "Second login closes")
    controller.openLogin { _ in firstClosed.fulfill() }
    let first = try loginWindow()
    first.close()
    controller.openLogin { _ in secondClosed.fulfill() }
    let second = try loginWindow()
    XCTAssertFalse(first === second)
    wait(for: [firstClosed], timeout: 10)
    XCTAssertTrue(second.isVisible)
    XCTAssertTrue(second.delegate === controller)
    second.close()
    wait(for: [secondClosed], timeout: 10)
  }

  private func loginWindow() throws -> NSWindow {
    try XCTUnwrap(NSApp.windows.first { $0.title == "登录 X" && $0.isVisible })
  }

}
