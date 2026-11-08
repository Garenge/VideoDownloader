import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';
import test from 'node:test';

const swift = readFileSync(new URL('../macos/Runner/XLikesScript.swift', import.meta.url), 'utf8');
const script = swift.split('#"""')[1].split('"""#')[0];
const endpoint = 'https://x.com/i/api/graphql/example/Likes?variables=' + encodeURIComponent(JSON.stringify({userId: '1', count: 20}));

function harness() {
  const messages = [];
  const requests = [];
  const window = {
    webkit: {messageHandlers: {xLikes: {postMessage: payload => messages.push(payload)}}},
    fetch: async (input, init) => {
      requests.push({input, init});
      return new Response('{"data":{}}', {status: 200});
    },
  };
  class XHR {
    open() {}
    setRequestHeader() {}
    addEventListener(name, callback) { (this.listeners ??= {})[name] = callback; }
    send() { this.status = 200; this.responseText = '{"data":{}}'; this.listeners?.load(); }
  }
  runInNewContext(script, {window, XMLHttpRequest: XHR, URL, Request,
    location: {href: 'https://x.com/i/history/likes'}});
  return {window, XHR, messages, requests};
}

test('captures XHR response and replays cursor without exposing auth headers', async () => {
  const {window, XHR, messages, requests} = harness();
  const xhr = new XHR();
  xhr.open('GET', endpoint);
  xhr.setRequestHeader('x-csrf-token', 'test-secret');
  xhr.send();
  assert.equal(messages[0].statusCode, 200);
  await window.__videoDownloaderNextLikes('page-2');
  assert.equal(requests[0].init.headers['x-csrf-token'], 'test-secret');
  assert.equal(requests[0].init.credentials, 'include');
  const variables = JSON.parse(new URL(requests[0].input).searchParams.get('variables'));
  assert.deepEqual(variables, {userId: '1', count: 20, cursor: 'page-2'});
  assert.equal(messages.length, 2);
  assert.ok(!JSON.stringify(messages).includes('test-secret'));
});

test('captures fetch responses without consuming original response', async () => {
  const {window, messages} = harness();
  const response = await window.fetch(new Request(endpoint, {headers: {'x-csrf-token': 'secret'}}));
  assert.equal(await response.text(), '{"data":{}}');
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(messages.length, 1);
  await window.__videoDownloaderNextLikes('page-2');
  assert.equal(messages.length, 2);
});

test('ignores unrelated and foreign-origin requests', async () => {
  const {window, XHR, messages} = harness();
  await window.fetch('https://example.com/i/api/graphql/id/Likes');
  const xhr = new XHR();
  xhr.open('GET', 'https://x.com/i/api/graphql/id/HomeTimeline');
  xhr.send();
  assert.equal(messages.length, 0);
  await window.__videoDownloaderNextLikes('next');
  assert.match(messages[0].error, /刷新/);
});
