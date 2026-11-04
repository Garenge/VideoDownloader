import JavaScriptCore
import WebKit
import XCTest
@testable import Runner

final class IosXSessionTests: XCTestCase {
  func testCookieDomainsRejectLookalikes() {
    XCTAssertTrue(IosXSession.isXDomain(".x.com"))
    XCTAssertTrue(IosXSession.isXDomain("api.twitter.com"))
    XCTAssertFalse(IosXSession.isXDomain("x.com.evil.example"))
    XCTAssertFalse(IosXSession.isXDomain("notx.com"))
  }

  func testLoginStatusAndLogoutPreserveUnrelatedCookies() throws {
    let session = IosXSession(store: .nonPersistent())
    let saved = expectation(description: "cookies written")
    let group = DispatchGroup()
    for domain in [".x.com", "example.com"] {
      let cookie = try XCTUnwrap(HTTPCookie(properties: [
        .domain: domain, .path: "/", .name: "auth_token", .value: "test-session",
        .secure: "TRUE", .expires: Date().addingTimeInterval(3600),
      ]))
      group.enter()
      session.store.httpCookieStore.setCookie(cookie) { group.leave() }
    }
    group.notify(queue: .main) { saved.fulfill() }
    wait(for: [saved], timeout: 5)
    let checked = expectation(description: "authenticated")
    session.status {
      XCTAssertEqual($0["authenticated"] as? Bool, true)
      checked.fulfill()
    }
    wait(for: [checked], timeout: 5)
    let cleared = expectation(description: "logout")
    session.logout { cleared.fulfill() }
    wait(for: [cleared], timeout: 5)
    let verified = expectation(description: "logged out")
    session.status {
      XCTAssertEqual($0["authenticated"] as? Bool, false)
      session.store.httpCookieStore.getAllCookies {
        XCTAssertEqual($0.map(\.domain), ["example.com"])
        verified.fulfill()
      }
    }
    wait(for: [verified], timeout: 5)
  }

  func testProxyValidationAndClear() throws {
    guard #available(iOS 17.0, *) else { return }
    let session = IosXSession(store: .nonPersistent())
    XCTAssertThrowsError(try session.configureProxy("http://localhost:99999"))
    XCTAssertThrowsError(try session.configureProxy("socks5://localhost:7890"))
    try session.configureProxy("http://127.0.0.1:7890")
    XCTAssertEqual(session.store.proxyConfigurations.count, 1)
    try session.configureProxy(nil)
    XCTAssertTrue(session.store.proxyConfigurations.isEmpty)
  }

  func testResponseObserverUsesOnlyTargetTweetAndTrustedHighestBitrateMp4() throws {
    let context = try XCTUnwrap(JSContext())
    context.evaluateScript("""
      var received = [];
      var window = {webkit: {messageHandlers: {xMedia: {
        postMessage: function(value) { received.push(value); }
      }}}};
      var document = {addEventListener: function() {}};
      function URL(value) {
        var match = /^(https?):\\/\\/([^/]+)(.*)$/.exec(value);
        if (!match) throw new Error('invalid');
        this.protocol = match[1] + ':';
        this.hostname = match[2];
        this.pathname = match[3];
      }
      function XMLHttpRequest() {}
      XMLHttpRequest.prototype.addEventListener = function(_, fn) {this.loaded = fn;};
      XMLHttpRequest.prototype.open = function() {};
    """)
    context.evaluateScript(IosXMediaScript.source(statusID: "123"))
    XCTAssertNil(context.exception)
    context.evaluateScript("""
      function video(url, bitrate) {return {content_type:'video/mp4', url:url, bitrate:bitrate};}
      function tweet(id, variants) {return {rest_id:id, legacy:{
        extended_entities:{media:[{video_info:{variants:variants}}]}
      }};}
      var xhr = new XMLHttpRequest();
      xhr.open('GET', '/');
      xhr.responseURL = 'https://x.com/i/api/graphql/operation/TweetDetail';
      xhr.responseText = JSON.stringify({entries:[
        tweet('999', [video('https://video.twimg.com/unrelated.mp4', 99999)]),
        tweet('123', [
          video('https://video.twimg.com/low.mp4', 100),
          video('https://video.twimg.com/high.mp4', 900),
          video('https://evil.example/secret.mp4', 99999)
        ])
      ]});
      xhr.loaded();
    """)
    XCTAssertNil(context.exception)
    let urls = context.evaluateScript("received[0].urls")?.toArray() as? [String]
    XCTAssertEqual(urls, ["https://video.twimg.com/high.mp4"])
  }
}
