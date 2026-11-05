import JavaScriptCore
import WebKit
import XCTest
@testable import Runner

final class IosXSessionTests: XCTestCase {
  func testNavigationInterruptionsDoNotAbortMediaExtraction() {
    for (domain, code) in [
      ("WebKitErrorDomain", 102),
      (NSURLErrorDomain, NSURLErrorCancelled),
    ] {
      XCTAssertTrue(IosXBrowserController.isNavigationInterruption(
        NSError(domain: domain, code: code)
      ))
    }
  }

  func testRealNavigationFailuresAreNotIgnored() {
    for (domain, code) in [
      (NSURLErrorDomain, NSURLErrorTimedOut),
      (NSURLErrorDomain, NSURLErrorCannotConnectToHost),
      (NSURLErrorDomain, NSURLErrorSecureConnectionFailed),
      ("WebKitErrorDomain", 101),
      ("OtherDomain", 102),
      ("OtherDomain", NSURLErrorCancelled),
    ] {
      XCTAssertFalse(IosXBrowserController.isNavigationInterruption(
        NSError(domain: domain, code: code)
      ))
    }
  }

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
    let context = try makeMediaContext()
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
    let urls = context.evaluateScript("received.find(value => value.urls).urls")?.toArray() as? [String]
    XCTAssertEqual(urls, ["https://video.twimg.com/high.mp4"])
  }

  func testMediaURLValidationAcceptsAttachmentsAndRejectsOtherResources() {
    for url in [
      "https://pbs.twimg.com/media/photo.jpg",
      "https://pbs.twimg.com/media/photo?format=png",
      "https://video.twimg.com/movie.mp4",
    ] {
      XCTAssertTrue(IosXBrowserController.isMediaURL(url), url)
    }
    for url in [
      "https://pbs.twimg.com/profile_images/avatar.jpg",
      "https://pbs.twimg.com.evil.example/media/photo.jpg",
      "http://pbs.twimg.com/media/photo.jpg",
      "https://video.twimg.com/movie.m3u8",
      "https://user@pbs.twimg.com/media/photo.jpg",
    ] {
      XCTAssertFalse(IosXBrowserController.isMediaURL(url), url)
    }
  }

  func testResponseObserverExtractsPhotosAndMixedMediaInAttachmentOrder() throws {
    let context = try makeMediaContext()
    context.evaluateScript("""
      window.__INITIAL_DATA__ = {entries:[
        {rest_id:'999', mediaDetails:[
          {type:'photo', media_url_https:'https://pbs.twimg.com/media/unrelated.jpg'}
        ]},
        {rest_id:'123', legacy:{extended_entities:{media:[
          {type:'photo', media_url_https:'https://pbs.twimg.com/media/first.jpg'},
          {type:'video', media_url_https:'https://pbs.twimg.com/media/cover.jpg',
            video_info:{variants:[
              {content_type:'video/mp4', url:'https://video.twimg.com/low.mp4', bitrate:100},
              {content_type:'video/mp4', url:'https://video.twimg.com/high.mp4', bitrate:900}
          ]}},
          {type:'photo', media_url_https:'https://pbs.twimg.com/media/second.png'},
          {type:'photo', media_url_https:'https://pbs.twimg.com/profile_images/avatar.jpg'},
          {type:'photo', media_url_https:'https://pbs.twimg.com.evil.example/media/bad.jpg'}
        ]}}, quoted_status_result:{result:{rest_id:'456', mediaDetails:[
          {type:'photo', media_url_https:'https://pbs.twimg.com/media/quoted.jpg'}
        ]}}}
      ]};
      listeners.DOMContentLoaded();
    """)
    XCTAssertNil(context.exception)
    XCTAssertEqual(context.evaluateScript(
      "received.find(value => value.urls).urls"
    )?.toArray() as? [String], [
      "https://pbs.twimg.com/media/first.jpg",
      "https://video.twimg.com/high.mp4",
      "https://pbs.twimg.com/media/second.png",
    ])
  }

  func testResponseObserverExtractsPhotoOnlyPost() throws {
    let context = try makeMediaContext()
    context.evaluateScript("""
      window.__INITIAL_DATA__ = {rest_id:'123', mediaDetails:[
        {type:'photo', media_url_https:'https://pbs.twimg.com/media/first.jpg'},
        {type:'photo', media_url_https:'https://pbs.twimg.com/media/second.png'}
      ]};
      listeners.DOMContentLoaded();
    """)
    XCTAssertNil(context.exception)
    XCTAssertEqual(context.evaluateScript(
      "received.find(value => value.urls).urls"
    )?.toArray() as? [String], [
      "https://pbs.twimg.com/media/first.jpg",
      "https://pbs.twimg.com/media/second.png",
    ])
  }

  func testShareVideoURLLoadsCanonicalPostWithoutTrackingQuery() throws {
    let url = try XCTUnwrap(URL(string:
      "https://x.com/xystjmg/status/2112513926726619548/video/1?s=52"
    ))
    let id = try XCTUnwrap(IosXLoginBridge.statusID(url))
    XCTAssertEqual(id, "2112513926726619548")
    XCTAssertEqual(IosXLoginBridge.postURL(url, statusID: id).absoluteString,
                   "https://x.com/xystjmg/status/2112513926726619548")
  }

  func testStreamedHydrationSurvivesScriptRemovalAndIgnoresOtherPosts() throws {
    let context = try makeMediaContext()
    context.evaluateScript("""
      var payload = {data:{entries:[
        {rest_id:'999', result:{mediaDetails:[{video_info:{variants:[
          {content_type:'video/mp4', url:'https://video.twimg.com/other.mp4'}
        ]}}]}},
        {rest_id:'123', result:{mediaDetails:[{video_info:{variants:[
          {content_type:'video/mp4', url:'https://video.twimg.com/streamed.mp4'}
        ]}}]}}
      ]}};
      var script = {nodeName:'SCRIPT', textContent:
        '($R=>$R[17].next({value:' + JSON.stringify(JSON.stringify(payload)) + '}))($R["tsr"])'};
      mutationCallback([{addedNodes:[script], removedNodes:[script]}]);
    """)
    XCTAssertNil(context.exception)
    XCTAssertEqual(context.evaluateScript(
      "received.find(value => value.urls).urls"
    )?.toArray() as? [String], ["https://video.twimg.com/streamed.mp4"])
  }

  func testInitialDataDecodesNestedJsonWithoutExecutingScripts() throws {
    let context = try makeMediaContext()
    context.evaluateScript("""
      window.__INITIAL_DATA__ = {value:JSON.stringify({rest_id:'123',
        mediaDetails:[{video_info:{variants:[
          {content_type:'video/mp4', url:'https://video.twimg.com/initial.mp4'}
        ]}}]})};
      scripts = [{textContent:'throw new Error("123 must not execute")'}];
      listeners.DOMContentLoaded();
    """)
    XCTAssertNil(context.exception)
    XCTAssertEqual(context.evaluateScript(
      "received.find(value => value.urls).urls"
    )?.toArray() as? [String], ["https://video.twimg.com/initial.mp4"])
  }

  private func makeMediaContext() throws -> JSContext {
    let context = try XCTUnwrap(JSContext())
    context.evaluateScript("""
      var received = [], scripts = [], listeners = {}, mutationCallback;
      var window = {webkit: {messageHandlers: {xMedia: {
        postMessage: function(value) { received.push(value); }
      }}}};
      var document = {
        addEventListener: function(name, fn) {listeners[name] = fn;},
        querySelectorAll: function() {return scripts;}
      };
      function MutationObserver(callback) {mutationCallback = callback; this.observe = function() {};}
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
    return context
  }
}
