const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(process.argv[2], 'utf8');
const token = html.match(/state\?key=([a-fA-F0-9-]+)/)[1];
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const messages = [];
let listener, interval;
const picture = {style: {}, src: 'original'};
class MockImage {
  set src(value) { this.value = value; this.onload(); }
  get src() { return this.value; }
}
const sandbox = {
  document: {getElementById: () => picture},
  window: {innerWidth: 517, innerHeight: 89, chrome: {webview: {
    addEventListener: (event, callback) => { listener = callback; },
    postMessage: message => messages.push(message)
  }}},
  setInterval: callback => { interval = callback; },
  fetch: async url => {
    assert.equal(url, 'https://serv.ds.kakao.com/talkframe/state?key=' + token + '&w=517&h=89');
    return {ok: true, json: async () => ({revision: 'new-version', fit: 'cover'})};
  },
  Image: MockImage,
  encodeURIComponent,
};
(async () => {
  vm.runInNewContext(script, sandbox);
  listener({data: {event: {name: 'ReadyToListen'}}});
  assert.equal(messages[0].event.name, 'AdLoaded');
  assert.equal(messages[0].event.data.result, true);
  await interval();
  assert.equal(picture.style.objectFit, 'cover');
  assert.equal(picture.src, 'https://serv.ds.kakao.com/talkframe/image?key=' + token + '&v=new-version');
  console.log('PASS JavaScript loading bridge and live image update');
})().catch(error => { console.error(error); process.exitCode = 1; });
