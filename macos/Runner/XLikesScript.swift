import Foundation

// Runs in the page world. Authentication headers stay inside the logged-in web view.
enum XLikesScript {
  static let source = #"""
  (() => {
    let template = null;
    let pending = false;
    const send = value => window.webkit.messageHandlers.xLikes.postMessage(value);
    const isLikes = value => {
      try {
        const url = new URL(value, location.href);
        return url.origin === 'https://x.com' && /^\/i\/api\/graphql\/[^/]+\/Likes$/.test(url.pathname);
      } catch (_) { return false; }
    };
    const originalFetch = window.fetch.bind(window);
    const report = async (response, url) => {
      try {
        send({statusCode: response.status, endpoint: url, rawJson: await response.text()});
      } catch (_) { send({error: 'X 点赞响应读取失败，请重试'}); }
    };
    window.fetch = async function(input, init) {
      const url = typeof input === 'string' ? input : (input.url || String(input));
      if (!isLikes(url)) return originalFetch(input, init);
      const request = new Request(input, init);
      template = {url: request.url, headers: Object.fromEntries(request.headers.entries())};
      const response = await originalFetch(request);
      if (!pending) report(response.clone(), request.url);
      return response;
    };
    const open = XMLHttpRequest.prototype.open;
    const setHeader = XMLHttpRequest.prototype.setRequestHeader;
    const sendXHR = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this.__xLikes = method.toUpperCase() === 'GET' && isLikes(url)
        ? {url: new URL(url, location.href).href, headers: {}} : null;
      return open.call(this, method, url, ...rest);
    };
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
      if (this.__xLikes) this.__xLikes.headers[name] = value;
      return setHeader.call(this, name, value);
    };
    XMLHttpRequest.prototype.send = function(...args) {
      if (this.__xLikes) {
        const request = this.__xLikes;
        this.addEventListener('load', () => {
          template = request;
          if (pending) return;
          let rawJson;
          try { rawJson = this.responseType === 'json' ? JSON.stringify(this.response) : this.responseText; }
          catch (_) { send({error: 'X 点赞响应读取失败，请重试'}); return; }
          send({statusCode: this.status, endpoint: request.url, rawJson});
        }, {once: true});
        this.addEventListener('error', () => {
          if (!pending) send({error: 'X 点赞请求失败，请检查网络后重试'});
        }, {once: true});
      }
      return sendXHR.apply(this, args);
    };
    window.__videoDownloaderNextLikes = async cursor => {
      if (!template || pending) {
        send({error: '点赞会话尚未就绪，请刷新列表'});
        return;
      }
      pending = true;
      try {
        const url = new URL(template.url);
        const variables = JSON.parse(url.searchParams.get('variables') || '{}');
        variables.cursor = cursor;
        url.searchParams.set('variables', JSON.stringify(variables));
        const response = await originalFetch(url.href, {
          headers: template.headers, credentials: 'include'
        });
        await report(response, url.href);
      } catch (_) { send({error: 'X 点赞分页请求失败，请检查网络后重试'}); }
      finally { pending = false; }
    };
  })();
  """#
}
