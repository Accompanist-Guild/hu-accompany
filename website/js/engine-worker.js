// The app's note detector (web_engine, WebAssembly) on its own thread. Messages in:
//   {type: 'start', piece, sampleRate, port}  follow `piece`; audio arrives on `port`
//   {type: 'finish'}                          the audio has ended
// Messages out: {type: 'ready'} | {type: 'notes', notes} | {type: 'finished', notes} | {type: 'error', message}
import init, { Engine } from '../engine/engine.js';

const loading = init({ module_or_path: new URL('../engine/engine_bg.wasm', import.meta.url) });
let engine = null, port = null;

function send(type, json) {
  const notes = JSON.parse(json);
  if (notes.length || type === 'finished') postMessage({ type, notes });
}

onmessage = async (e) => {
  const msg = e.data;
  try {
    await loading;
    if (msg.type === 'warm') { postMessage({ type: 'ready' }); return; }
    if (msg.type === 'start') {
      if (port) port.onmessage = null;
      engine = new Engine(JSON.stringify(msg.piece), msg.sampleRate);
      port = msg.port;
      port.onmessage = (a) => { if (engine) send('notes', engine.push(a.data)); };
      postMessage({ type: 'ready' });
    } else if (msg.type === 'finish') {
      if (port) port.onmessage = null;
      port = null;
      const json = engine ? engine.finish() : '[]';
      engine = null;
      send('finished', json);
    }
  } catch (err) {
    postMessage({ type: 'error', message: String(err && err.message || err) });
  }
};
