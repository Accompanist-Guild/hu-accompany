// The app's LiveJudge tests (frontend/test/score_practice_test.dart), run against the website's
// port:  node --test website/js/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LiveJudge, Result, layout } from './judge.js';

// The opening of Für Elise as score_timeline.js reads it (3/8, 72 bpm, a pickup bar 0).
function elise() {
  const rh = [76, 75, 76, 75, 76, 71, 74, 72];
  const notes = rh.map((midi, i) => ({ id: i + 1, midi, startMs: i * 208.3, durationMs: 208.3,
    measureNumber: i < 2 ? 0 : 1, visit: i < 2 ? 0 : 1, staff: 0 }));
  notes.push(
    { id: 9, midi: 45, startMs: 1666.7, durationMs: 208.3, measureNumber: 2, visit: 2, staff: 1 },
    { id: 10, midi: 69, startMs: 1666.7, durationMs: 416.7, measureNumber: 2, visit: 2, staff: 0 },
    { id: 11, midi: 52, startMs: 1875.0, durationMs: 208.3, measureNumber: 2, visit: 2, staff: 1 },
    { id: 12, midi: 57, startMs: 2083.3, durationMs: 208.3, measureNumber: 2, visit: 2, staff: 1 });
  return { notes, bpm: 72, timeSignature: '3/8', staves: 2 };
}
// Two bars with a repeat sign, then a third: played 0 1 0 1 2, 300 ms a note, at 60 bpm.
function repeated() {
  const measures = [0, 0, 1, 1, 0, 0, 1, 1, 2, 2];
  return { notes: measures.map((m, i) => ({ id: i + 1, midi: 60 + i, startMs: i * 300, durationMs: 300,
    measure: m, measureNumber: m + 1, visit: Math.floor(i / 2), staff: 0 })), bpm: 60, timeSignature: '2/4', staves: 1 };
}
const heard = (id, startMs, { endMs = null, hz = 440 } = {}) =>
  ({ note_id: id, pitch_hz: hz, start_time_ms: startMs, end_time_ms: endMs });
const t0 = 1000;

const fresh = () => { const notes = layout(elise(), 72); return { notes, judge: new LiveJudge(notes, 72) }; };

test('before anything is played, the opening note is due', () => {
  const { judge } = fresh();
  assert.deepEqual(judge.due(t0), [1]);
});

test('a little off is close; further off is early or late', () => {
  const { judge } = fresh();
  judge.add([heard(1, 50)], t0);
  judge.add([heard(2, 208 + 100)], t0);
  judge.add([heard(3, 417 - 200)], t0);
  judge.add([heard(4, 625 + 200)], t0);
  assert.equal(judge.marks.get(1).result, Result.perfect);
  assert.equal(judge.marks.get(2).result, Result.close);
  assert.equal(judge.marks.get(3).result, Result.early);
  assert.equal(judge.marks.get(4).result, Result.late);
  assert.equal(judge.describe(4), 'D♯ came late by 200 ms');
});

test('a note never played is missed once a later one is', () => {
  const { judge } = fresh();
  judge.add([heard(1, 0)], t0);
  const update = judge.add([heard(3, 417)], t0);
  assert.equal(update.marks.get(2).result, Result.missed);
  assert.equal(update.marks.get(3).result, Result.perfect);
  assert.equal(judge.describe(2), 'D♯ was not played');
});

test('a note heard a moment after a later one is not counted missed', () => {
  const { notes, judge } = fresh();
  for (let id = 1; id <= 8; id++) judge.add([heard(id, notes[id - 1].startMs)], t0);
  assert.equal(judge.add([heard(10, 1666.7)], t0).marks.has(9), false);
  assert.equal(judge.add([heard(9, 1670)], t0).marks.get(9).result, Result.perfect);
});

test('a wrong key marks the note it replaced, with the key played', () => {
  const { judge } = fresh();
  judge.add([heard(1, 0), heard(2, 208)], t0);
  const update = judge.add([heard(0, 420, { hz: 587.33 })], t0);
  assert.equal(update.marks.get(3).result, Result.wrong);
  assert.equal(update.marks.get(3).playedMidi, 74);
  assert.equal(judge.describe(3), 'Played D instead of E');
  assert.deepEqual([...judge.add([heard(4, 625)], t0).marks.keys()], [4]);
});

test('a wrong key then the right one is still a mistake; at the same moment it is right', () => {
  let { judge } = fresh();
  judge.add([heard(1, 0), heard(2, 208)], t0);
  judge.add([heard(0, 380, { hz: 587.33 })], t0);
  assert.equal(judge.add([heard(3, 560)], t0).marks.has(3), false);
  assert.equal(judge.marks.get(3).result, Result.wrong);
  ({ judge } = fresh());
  judge.add([heard(1, 0), heard(2, 208)], t0);
  judge.add([heard(0, 410, { hz: 587.33 })], t0);
  judge.add([heard(3, 420)], t0);
  assert.equal(judge.marks.get(3).result, Result.perfect);
});

test('notes due follow the player on between reports', () => {
  const { judge } = fresh();
  judge.add([heard(1, 0)], t0);
  assert.deepEqual(judge.due(t0), [2]);
  assert.deepEqual(judge.due(t0 + 300), [2, 3, 4]);
  assert.equal(judge.due(t0 + 300), null);
});

test('starting again from a note keeps what came before it', () => {
  const { judge } = fresh();
  judge.add([heard(1, 0), heard(2, 208), heard(3, 417), heard(4, 625)], t0);
  const update = judge.restartFrom(3);
  assert.deepEqual(update.cleared, [3, 4]);
  assert.deepEqual([...judge.marks.keys()], [1, 2]);
  assert.equal(judge.next(), 3);
  assert.deepEqual(update.due, [3]);
  judge.add([heard(3, 417), heard(5, 833)], t0);
  assert.equal(judge.marks.get(4).result, Result.missed);
});

test('repeats: sections with each time through, announced once', () => {
  const notes = layout(repeated(), 60);
  assert.deepEqual(notes.map((n) => n.pass), [0, 0, 0, 0, 1, 1, 1, 1, 0, 0]);
  const judge = new LiveJudge(notes, 60);
  assert.equal(judge.sections.length, 2);
  assert.equal(judge.sections[0].bars, 'Bars 1–2');
  assert.deepEqual(judge.sections[0].times, [[1, 2, 3, 4], [5, 6, 7, 8]]);
  assert.equal(judge.repeatStarting(), null);
  judge.add([1, 2, 3, 4].map((i) => heard(i, (i - 1) * 300)));
  assert.deepEqual(judge.repeatStarting(), [5, 6, 7, 8]);
  assert.equal(judge.repeatStarting(), null);
  const again = new LiveJudge(notes, 60);
  for (let i = 1; i <= 6; i++) again.add([heard(i, (i - 1) * 300)]);
  again.repeatStarting();
  assert.deepEqual(again.restartFrom(7).showPass, [5, 6, 7, 8]);
});

test('the score counts what was played', () => {
  const { judge } = fresh();
  judge.add([heard(1, 0)], t0);
  judge.add([heard(3, 417)], t0);
  assert.equal(judge.score(), 67);
});

test('plays one hand alone', () => {
  assert.deepEqual(layout(elise(), 72, 'right').map((n) => n.noteId), [1, 2, 3, 4, 5, 6, 7, 8, 10]);
  assert.deepEqual(layout(elise(), 72, 'left').map((n) => n.noteId), [9, 11, 12]);
});
