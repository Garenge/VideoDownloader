import Foundation

enum IosXMediaScript {
  // Observe responses produced by X's own webpage, using its existing login session.
  // Only extract media belonging to the requested tweet, never quoted/recommended tweets.
  static func source(statusID: String) -> String {
    return """
    (() => {
      const wanted = '\(statusID)';
      const send = value => window.webkit.messageHandlers.xMedia.postMessage(value);
      const valid = value => {
        try {
          const u = new URL(value);
          return u.protocol === 'https:' &&
            (u.hostname === 'video.twimg.com' || u.hostname.endsWith('.video.twimg.com'));
        } catch (_) { return false; }
      };
      const mediaFrom = tweet => {
        const legacy = tweet.legacy || tweet;
        const media = legacy.extended_entities?.media || legacy.entities?.media ||
          tweet.mediaDetails || [];
        return media.map(item => {
          const variants = (item.video_info?.variants || [])
            .filter(v => v.content_type === 'video/mp4' && valid(v.url))
            .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));
          return variants[0]?.url;
        }).filter(Boolean);
      };
      const inspect = root => {
        const stack = [root];
        const found = new Set();
        let count = 0;
        while (stack.length && count++ < 50000) {
          const node = stack.pop();
          if (!node || typeof node !== 'object') continue;
          if (String(node.rest_id || node.id_str || node.legacy?.id_str || '') === wanted) {
            mediaFrom(node).forEach(url => found.add(url));
          }
          Object.values(node).forEach(value => {
            if (value && typeof value === 'object') stack.push(value);
          });
        }
        if (found.size) send({urls: [...found]});
      };
      const read = text => { try { inspect(JSON.parse(text)); } catch (_) {} };
      const originalFetch = window.fetch;
      window.fetch = function(...args) {
        return originalFetch.apply(this, args).then(response => {
          try {
            const u = new URL(response.url);
            if ((u.hostname === 'x.com' || u.hostname === 'api.x.com') &&
                u.pathname.includes('/graphql/')) response.clone().text().then(read).catch(() => {});
          } catch (_) {}
          return response;
        });
      };
      const originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(...args) {
        this.addEventListener('load', () => {
          try {
            const u = new URL(this.responseURL);
            if ((u.hostname === 'x.com' || u.hostname === 'api.x.com') &&
                u.pathname.includes('/graphql/')) {
              if (this.responseType === 'json') inspect(this.response);
              else if (!this.responseType || this.responseType === 'text') read(this.responseText);
            }
          } catch (_) {}
        });
        return originalOpen.apply(this, args);
      };
      document.addEventListener('DOMContentLoaded', () => {
        if (window.__INITIAL_STATE__) inspect(window.__INITIAL_STATE__);
      });
    })();
    """
  }
}
