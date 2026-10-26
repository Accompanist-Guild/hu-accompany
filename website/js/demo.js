// The website's one free play-along: the app's score page (viewer/, in an iframe), the app's
// note detector (engine-worker.js) and the app's judging (judge.js), wired the way
// frontend/lib/main.dart wires them for a score. Everything runs in the visitor's browser.
import { LiveJudge, isMistake, layout, pieceData, timeName } from './judge.js';

const SCORE_URL = 'scores/fur-elise.musicxml';
const TITLE = 'Für Elise';
const USED_KEY = 'accompanist.demo.used';
const TICK_MS = 80;

const $ = (id) => document.getElementById(id);
const frame = $('score-frame');
const startButton = $('demo-start');
const status = $('demo-status');
const handsSelect = $('demo-hands');

// ── The score page ─────────────────────────────────────────────────────────
let bridge = null;          // the page's OSMDBridge, once it says it is ready
const queued = [];
let timeline = null;

function call(fn) { if (bridge) fn(bridge); else queued.push(fn); }

// The page says it's ready once; it may have said so before this script ran.
function connect() {
  const ready = frame.contentWindow && frame.contentWindow.OSMDBridge;
  if (bridge || !ready) return;
  bridge = ready;
  fetch(SCORE_URL).then((r) => r.text()).then((xml) => {
    bridge.loadScore(xml);
    queued.splice(0).forEach((fn) => fn(bridge));
  });
}
frame.addEventListener('load', connect);

window.addEventListener('message', (e) => {
  if (e.source !== frame.contentWindow || !e.data || !e.data.accompanist) return;
  const { type, payload } = e.data.accompanist;
  if (type === 'bridgeReady') {
    connect();
  } else if (type === 'timeline') {
    timeline = payload;
    if (!timeline.notes || !timeline.notes.length) return say('This score could not be read.');
    ready();
  } else if (type === 'screenTap') {
    if (state === 'listening') (payload.count >= 2 ? finish : pause)();
  } else if (type === 'noteTap') {
    showNote(payload.ids);
  } else if (type === 'error') {
    say('The score could not be shown: ' + payload.message);
  }
});

function live(update) {
  const marks = [];
  if (update.marks) for (const [id, v] of update.marks) marks.push({ id, r: v.result, played: v.playedMidi });
  call((b) => b.live({
    marks, cleared: update.cleared, due: update.due ?? undefined, played: update.played,
    repeat: update.repeat ?? undefined, showPass: update.showPass ?? undefined, follow: state === 'listening',
  }));
}

// ── State ──────────────────────────────────────────────────────────────────
// idle → counting → listening ⇄ paused → finished (one go per visitor)
let state = 'loading';
let judge = null, notes = [], bpm = 0;
let audio = null;           // {ctx, stream, node}
let worker = null, ticker = null, onFinished = null;

function say(text) { status.textContent = text || ''; }

function used() { try { return localStorage.getItem(USED_KEY) === '1'; } catch { return false; } }
function markUsed() { try { localStorage.setItem(USED_KEY, '1'); } catch { /* private mode: no memory */ } }

function supported() {
  // WebAssembly SIMD (the engine is built with it) and AudioWorklet.
  const simd = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11]);
  return typeof AudioWorkletNode === 'function' && WebAssembly.validate(simd) && !!navigator.mediaDevices?.getUserMedia;
}

function ready() {
  if (state !== 'loading') return;
  state = 'idle';
  if (new URLSearchParams(location.search).has('again')) { try { localStorage.removeItem(USED_KEY); } catch {} }
  if (used()) return showUsed();
  if (!supported()) {
    startButton.disabled = true;
    return say('Your browser can’t run the demo. Try a recent Chrome, Edge, Firefox or Safari.');
  }
  if (timeline.staves < 2) handsSelect.hidden = true;
  startButton.disabled = false;
  say('');
  // The engine (about 4 MB) loads while the visitor reads.
  worker = new Worker(new URL('./engine-worker.js', import.meta.url), { type: 'module' });
  worker.onmessage = onWorker;
  worker.postMessage({ type: 'warm' });
}

function showUsed() {
  document.body.classList.add('demo-used');
  startButton.disabled = true;
  say('');
}

function onWorker(e) {
  const msg = e.data;
  if (msg.type === 'notes') heard(msg.notes);
  else if (msg.type === 'finished') { heard(msg.notes); const done = onFinished; onFinished = null; done?.(); }
  else if (msg.type === 'error') { say('The listening engine stopped: ' + msg.message); stopAudio(); }
}

// ── Playing ────────────────────────────────────────────────────────────────
startButton.addEventListener('click', async () => {
  if (state !== 'idle' || !timeline) return;
  startButton.disabled = true;
  try {
    say('Allow the microphone when your browser asks.');
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    });
    const ctx = new AudioContext();
    await ctx.audioWorklet.addModule(new URL('./capture-worklet.js', import.meta.url));
    const node = new AudioWorkletNode(ctx, 'accompanist-capture');
    ctx.createMediaStreamSource(stream).connect(node);
    audio = { ctx, stream, node };
    say('');
  } catch (err) {
    startButton.disabled = false;
    return say(err && err.name === 'NotAllowedError'
      ? 'The demo needs the microphone to hear you. Allow it and try again.'
      : 'Could not open the microphone: ' + (err && err.message || err));
  }
  bpm = Math.round(timeline.bpm);
  notes = layout(timeline, bpm, handsSelect.value);
  judge = new LiveJudge(notes, bpm);
  call((b) => b.resetLive());
  handsSelect.disabled = true;
  await listenFrom(null);
});

/** Loads the notes from `fromId` on into the engine, counts the player in, then listens. */
async function listenFrom(fromId) {
  const from = fromId == null ? null : judge.note(fromId);
  const remaining = notes.filter((n) => !from || n.startMs >= from.startMs);
  live(judge.restartFrom(fromId));
  const channel = new MessageChannel();
  worker.postMessage({ type: 'start', piece: pieceData(TITLE, bpm, remaining), sampleRate: audio.ctx.sampleRate, port: channel.port2 }, [channel.port2]);
  if (audio.ctx.state === 'suspended') await audio.ctx.resume();

  state = 'counting';
  enterPlaying();
  await countIn();
  if (state !== 'counting') return;
  audio.node.port.postMessage({ port: channel.port1 }, [channel.port1]);
  state = 'listening';
  call((b) => b.setImmersive(true));
  live({ due: judge.due() });
  flashHint();
  ticker = setInterval(() => {
    const due = judge.due(), repeat = judge.repeatStarting();
    if (due || repeat) live({ due, repeat });
  }, TICK_MS);
}

/** One bar of the score's metre (two of a short one), in its beat: ScorePracticeSession._countIn. */
async function countIn() {
  const [top0, bottom] = (timeline.timeSignature || '4/4').split('/').map(Number);
  let top = top0 || 4, beatQuarters = 4 / (bottom || 4);
  if (bottom === 8 && top % 3 === 0 && top > 3) { top /= 3; beatQuarters *= 3; }
  if (top < 3) top *= 2;
  const beatMs = beatQuarters * 60000 / bpm;
  const shown = $('countin');
  for (let i = 1; i <= top; i++) {
    if (state !== 'counting') break;
    shown.textContent = i;
    shown.classList.remove('beat'); void shown.offsetWidth; shown.classList.add('beat');
    await new Promise((r) => setTimeout(r, i < top ? beatMs : beatMs / 2));
  }
  shown.textContent = '';
}

function heard(batch) {
  if (!judge || !batch.length) return;
  const { marks, played } = judge.add(batch);
  const due = judge.due(), repeat = judge.repeatStarting();
  if (marks.size || played.length || due || repeat) live({ marks, played, due, repeat });
}

/** Stops sending audio; resolves once the engine has handed over its last notes. */
function stopListening() {
  clearInterval(ticker); ticker = null;
  audio.node.port.postMessage({ port: null });
  call((b) => b.setImmersive(false));
  live({ due: [] });
  return new Promise((resolve) => { onFinished = resolve; worker.postMessage({ type: 'finish' }); });
}

async function pause() {
  if (state !== 'listening') return;
  state = 'paused';
  // As in the app: a pause brings the page back, with Go on and Finish over the score.
  leavePlaying();
  document.body.classList.add('demo-paused');
  await stopListening();
}

async function goOn() {
  if (state !== 'paused') return;
  document.body.classList.remove('demo-paused');
  const next = judge.next();
  if (next == null) return finish();
  await listenFrom(next);
}

async function finish() {
  if (state !== 'listening' && state !== 'paused' && state !== 'counting') return;
  const wasListening = state === 'listening';
  state = 'finished';
  document.body.classList.remove('demo-paused');
  if (wasListening) await stopListening();
  stopAudio();
  leavePlaying();
  markUsed();
  showSummary();
}

function stopAudio() {
  if (!audio) return;
  audio.stream.getTracks().forEach((t) => t.stop());
  audio.ctx.close();
  audio = null;
}

$('pause-go-on').addEventListener('click', goOn);
$('pause-finish').addEventListener('click', finish);
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape' && state === 'listening') pause();
});

// Full screen while playing: only the music (main.dart's immersive mode).
function enterPlaying() {
  document.body.classList.add('demo-playing');
  $('demo').scrollIntoView({ block: 'start' });
}
function leavePlaying() { document.body.classList.remove('demo-playing'); }

let hintTimer = null;
function flashHint() {
  const hint = $('tap-hint');
  hint.classList.add('show');
  clearTimeout(hintTimer);
  hintTimer = setTimeout(() => hint.classList.remove('show'), 3200);
}

// ── After the run ──────────────────────────────────────────────────────────
function showNote(ids) {
  if (!judge || state === 'listening' || state === 'counting') return;
  const marked = ids.filter((id) => judge.marks.has(id));
  if (!marked.length) return;
  const id = Math.max(...marked);
  call((b) => b.showTip(id, [`${judge.describe(id)} · bar ${LiveJudge.bar(judge.note(id))}`]));
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text != null) e.textContent = text;
  return e;
}

function mistakeRow(id) {
  const row = el('button', 'mistake');
  row.type = 'button';
  row.append(el('span', 'mistake-bar', `Bar ${LiveJudge.bar(judge.note(id))}`), el('span', 'mistake-text', judge.describe(id)));
  row.addEventListener('click', () => { closeSummary(); review(); showTime(id); call((b) => b.spotlight(id)); });
  return row;
}

function showSummary() {
  const c = judge.counts();
  const total = Object.values(c).reduce((a, b) => a + b, 0);
  const mistakes = c.early + c.late + c.wrong + c.missed;
  $('sum-score').textContent = judge.score();
  $('sum-right').textContent = total ? `${c.perfect + c.close} of ${total} notes right` : 'nothing heard';
  $('sum-perfect').textContent = c.perfect;
  $('sum-close').textContent = c.close;
  $('sum-mistakes').textContent = mistakes;

  const list = $('sum-list');
  list.replaceChildren();
  const reached = (ids) => ids.some((id) => judge.marks.has(id));
  const bad = (id) => judge.marks.has(id) && isMistake(judge.marks.get(id).result);
  const sections = judge.sections.filter((s) => s.times.some(reached));
  if (!mistakes) list.append(el('p', 'sum-clean', total ? 'No mistakes. Try it a little faster next time.' : 'Play along with the score and your run shows up here.'));
  for (const s of sections) {
    if (s.times.length > 1) {
      const times = s.times.map((ids, i) => [ids, i]).filter(([ids]) => reached(ids));
      const box = el('details', 'sum-repeat');
      const count = (ids) => { const n = ids.filter(bad).length; return n ? `${n} ${n === 1 ? 'mistake' : 'mistakes'}` : 'clean'; };
      const head = el('summary');
      head.append(el('span', 'sum-repeat-title', `${s.bars} · played ${s.times.length} times`),
        el('span', 'sum-repeat-sub', times.map(([ids, i]) => `${timeName(i)}: ${count(ids)}`).join(' · ')));
      box.append(head);
      for (const [ids, i] of times) {
        box.append(el('h4', null, timeName(i)));
        const wrong = ids.filter(bad);
        if (!wrong.length) box.append(el('p', 'sum-clean', 'No mistakes'));
        wrong.forEach((id) => box.append(mistakeRow(id)));
      }
      list.append(box);
    } else {
      const wrong = s.times[0].filter(bad);
      if (!wrong.length) continue;
      if (sections.length > 1) list.append(el('h4', null, s.bars));
      wrong.forEach((id) => list.append(mistakeRow(id)));
    }
  }
  $('summary').showModal();
}

function closeSummary() { $('summary').close(); }
$('sum-review').addEventListener('click', () => { closeSummary(); review(); });
$('sum-close-btn').addEventListener('click', closeSummary);
$('summary').addEventListener('close', () => { if (!document.body.classList.contains('demo-reviewing')) showUsed(); });

// Looking back over the run on the score, a repeat's times through switchable.
function review() {
  document.body.classList.add('demo-reviewing');
  const bar = $('review-times');
  bar.replaceChildren();
  judge.sections.forEach((s) => {
    const times = s.times.map((ids, i) => [ids, i]).filter(([ids]) => ids.some((id) => judge.marks.has(id)));
    if (times.length < 2) return;
    const group = el('span', 'review-group');
    group.append(el('span', 'review-label', s.bars));
    times.forEach(([ids, i]) => {
      const chip = el('button', 'chip', timeName(i));
      chip.type = 'button';
      chip.dataset.section = s.bars;
      chip.addEventListener('click', () => {
        group.querySelectorAll('.chip').forEach((c) => c.classList.toggle('on', c === chip));
        call((b) => b.live({ showPass: ids }));
      });
      if (i === times[times.length - 1][1]) chip.classList.add('on');
      group.append(chip);
    });
    bar.append(group);
  });
}

function showTime(id) {
  const s = judge.sections.find((sec) => sec.times.some((ids) => ids.includes(id)));
  if (s && s.times.length > 1) call((b) => b.live({ showPass: s.times.find((ids) => ids.includes(id)) }));
}

$('review-summary').addEventListener('click', () => $('summary').showModal());
$('review-done').addEventListener('click', () => { document.body.classList.remove('demo-reviewing'); showUsed(); });

connect();

$('zoom-in').addEventListener('click', () => call((b) => b.zoomBy(1.2)));
$('zoom-out').addEventListener('click', () => call((b) => b.zoomBy(1 / 1.2)));
