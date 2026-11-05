import Foundation

enum IosXMediaScript {
  // Observe responses produced by X's own webpage, using its existing login session.
  // Only extract media belonging to the requested tweet, never quoted/recommended tweets.
  static func source(statusID: String) -> String {
    return """
    (() => {
      const wanted = '\(statusID)';
      const send = value => window.webkit.messageHandlers.xMedia.postMessage(value);
      const phase = value => send({phase: value});
      const valid = (value, photo = false) => {
        try {
          const u = new URL(value);
          return u.protocol === 'https:' && (photo
            ? u.hostname === 'pbs.twimg.com' && u.pathname.startsWith('/media/')
            : (u.hostname === 'video.twimg.com' || u.hostname.endsWith('.video.twimg.com')) &&
              u.pathname.toLowerCase().endsWith('.mp4'));
        } catch (_) { return false; }
      };
      const mediaFrom = tweet => {
        const result = tweet.result || tweet;
        const legacy = result.legacy || result;
        const media = legacy.extended_entities?.media || legacy.entities?.media ||
          result.mediaDetails || [];
        return media.map(item => {
          if (item.type === 'photo') {
            return valid(item.media_url_https, true) ? item.media_url_https : null;
          }
          const variants = (item.video_info?.variants || [])
            .filter(v => v.content_type === 'video/mp4' && valid(v.url))
            .sort((a, b) => (b.bitrate || 0) - (a.bitrate || 0));
          return variants[0]?.url;
        }).filter(Boolean);
      };
      const inspect = root => {
        const stack = [root];
        const found = new Set();
        const visited = new Set();
        let count = 0;
        while (stack.length && count++ < 50000) {
          const node = stack.pop();
          if (typeof node === 'string' && /^[\\s]*[\\[{]/.test(node)) {
            try { stack.push(JSON.parse(node)); } catch (_) {}
            continue;
          }
          if (!node || typeof node !== 'object') continue;
          if (visited.has(node)) continue;
          visited.add(node);
          if (String(node.rest_id || node.id_str || node.legacy?.id_str || '') === wanted) {
            phase('tweet_received');
            mediaFrom(node).forEach(url => found.add(url));
          }
          Object.values(node).forEach(value => {
            if (value && (typeof value === 'object' || typeof value === 'string')) stack.push(value);
          });
        }
        if (found.size) send({urls: [...found]});
      };
      const read = text => { try { inspect(JSON.parse(text)); } catch (_) {} };
      // The current X frontend streams Relay JSON as quoted strings in scripts.
      // Decode data literals only; never evaluate webpage source.
      const readScript = script => {
        const text = script.textContent || '';
        if (!text.includes(wanted)) return;
        read(text);
        const literals = text.match(/"(?:\\\\.|[^"\\\\])*"/g) || [];
        for (const literal of literals) {
          try {
            const value = JSON.parse(literal);
            if (typeof value === 'string' && /^[\\s]*[\\[{]/.test(value)) read(value);
          } catch (_) {}
        }
      };
      const scanPage = () => {
        inspect(window.__INITIAL_STATE__);
        inspect(window.__INITIAL_DATA__);
        if (document.querySelectorAll) document.querySelectorAll('script').forEach(readScript);
      };
      if (typeof MutationObserver !== 'undefined') {
        new MutationObserver(records => {
          for (const record of records) {
            for (const node of record.addedNodes) {
              if (node.nodeName === 'SCRIPT') readScript(node);
              else if (node.parentNode?.nodeName === 'SCRIPT') readScript(node.parentNode);
            }
          }
        }).observe(document, {subtree: true, childList: true});
      }
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
      document.addEventListener('DOMContentLoaded', scanPage);
      document.addEventListener('x-web:bootstrap-data', scanPage);
      phase('observer_ready');
    })();
    """
  }
}
