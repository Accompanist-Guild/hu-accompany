// The app's note-by-note judging, for the website's play-along. A line-for-line port of
// frontend/lib/features/practice/score_timeline.dart (layout) and live_judge.dart (LiveJudge):
// change those and this together, so the website grades exactly like the app.

export const Result = Object.freeze({
  perfect: 'perfect', close: 'close', early: 'early', late: 'late', wrong: 'wrong', missed: 'missed',
});
const MISTAKES = new Set([Result.early, Result.late, Result.wrong, Result.missed]);
export const isMistake = (r) => MISTAKES.has(r);

const NAMES = ['C', 'C♯', 'D', 'D♯', 'E', 'F', 'F♯', 'G', 'G♯', 'A', 'A♯', 'B'];
export const noteName = (midi) => NAMES[((midi % 12) + 12) % 12];
export const midiToHz = (midi) => 440 * Math.pow(2, (midi - 69) / 12);
const midiOf = (hz) => Math.round(69 + 12 * Math.log2(hz / 440));

// ── Layout (score_timeline.dart) ─────────────────────────────────────────

/** Bars are judged together until they span at least this long. */
const PHRASE_MS = 4000;

/** Which staves a hand plays (Hands in score_timeline.dart): 0 is the top staff. */
const PLAYS = { both: () => true, right: (staff) => staff === 0, left: (staff) => staff >= 1 };

/**
 * The notes to play at `bpm` with `hands` ('both' | 'right' | 'left'), in time order, from the
 * timeline the score page posts ({notes, bpm, timeSignature, staves}).
 */
export function layout(timeline, bpm, hands = 'both') {
  const scale = timeline.bpm / bpm;
  const plays = (timeline.staves ?? 1) >= 2 ? PLAYS[hands] : PLAYS.both;
  const played = timeline.notes.filter((j) => plays(j.staff ?? 0)).map((j) => ({
    id: j.id, midi: j.midi, startMs: j.startMs, durationMs: j.durationMs,
    measureNumber: j.measureNumber ?? 1, visit: j.visit ?? 0,
    measure: j.measure ?? j.visit ?? 0, grace: j.grace === true,
  }));
  if (!played.length) return [];

  const phraseOfVisit = new Map();
  let phrase = 0, phraseStart = played[0].startMs, lastVisit = played[0].visit;
  for (const n of played) {
    if (n.visit !== lastVisit) {
      if (n.startMs - phraseStart >= PHRASE_MS / scale) { phrase++; phraseStart = n.startMs; }
      lastVisit = n.visit;
    }
    if (!phraseOfVisit.has(n.visit)) phraseOfVisit.set(n.visit, phrase);
  }
  const visitsOfMeasure = new Map();
  for (const n of played) {
    const visits = visitsOfMeasure.get(n.measure) ?? [];
    if (!visits.includes(n.visit)) visits.push(n.visit);
    visitsOfMeasure.set(n.measure, visits);
  }
  const lastOfPhrase = new Map();
  for (const n of played) lastOfPhrase.set(phraseOfVisit.get(n.visit), n.id);
  return played.map((n) => ({
    noteId: n.id, midi: n.midi, pitchHz: midiToHz(n.midi),
    startMs: n.startMs * scale, durationMs: n.durationMs * scale,
    bar: phraseOfVisit.get(n.visit),
    isEnd: lastOfPhrase.get(phraseOfVisit.get(n.visit)) === n.id,
    printedBar: n.measureNumber < 1 ? 1 : n.measureNumber,
    grace: n.grace, measure: n.measure,
    pass: visitsOfMeasure.get(n.measure).indexOf(n.visit),
  }));
}

/** native_ffi's PieceData for `notes`, following the player's tempo. */
export function pieceData(title, bpm, notes) {
  return {
    piece_name: title, curr_phase: 0, instrument: null, curr_music_phrase: 0,
    timing: { bpm, beat_unit: 4 }, follow_tempo: true,
    notes: notes.map((n) => ({
      note_id: n.noteId, pitch_hz: n.pitchHz, start_time_ms: n.startMs,
      end_time_ms: n.startMs + n.durationMs, duration_ms: n.durationMs, is_end: n.isEnd,
      vibrato_depth: null, pedal_action: null, has_accent: null, markings: null,
    })),
  };
}

// ── Judging (live_judge.dart) ────────────────────────────────────────────

const CHORD_MS = 60;
const MISSED_AFTER_MS = 150;
const STRAY_REACH_MS = 150;
const CORRECTED_AFTER_MS = 120;
const REPORT_LAG_MS = 350;
const MAX_RUN_ON_MS = 1500;
const JITTER_MS = 40;
/** Strictness.normal. */
const PERFECT_SHARE = 0.10, CLOSE_SCALE = 1.0;

export class LiveJudge {
  constructor(notes, bpm) {
    this.notes = [...notes].sort((a, b) => a.startMs - b.startMs);
    this.beatMs = 60000 / bpm;
    this.byId = new Map(this.notes.map((n) => [n.noteId, n]));
    /** id -> {result, playedMidi, offMs} */
    this.marks = new Map();
    this.heard = new Set();
    this.strays = new Map();
    this.fromMs = -Infinity;
    this.lastStartMs = null;
    this.lastHeardAt = null;
    this.dueIds = [];
    this.announced = new Set();
    this.findRuns();
  }

  note(id) { return this.byId.get(id); }
  perfectMs() { return Math.max(JITTER_MS, PERFECT_SHARE * this.beatMs); }
  closeMs(n) {
    const room = Math.min(250, Math.max(120, 0.6 * Math.min(n.durationMs, this.beatMs)));
    return Math.max(this.perfectMs(), room * CLOSE_SCALE);
  }
  static bar(n) { return n.printedBar ?? n.bar + 1; }

  findRuns() {
    this.runs = []; this.runOf = new Map();
    const passOfRun = [];
    for (const n of this.notes) {
      if (!this.runs.length || passOfRun[passOfRun.length - 1] !== n.pass) { this.runs.push([]); passOfRun.push(n.pass); }
      this.runs[this.runs.length - 1].push(n.noteId);
      this.runOf.set(n.noteId, this.runs.length - 1);
    }
    const bars = (r) => new Set(this.runs[r].map((id) => this.byId.get(id).measure ?? -1));
    const sectionOfRun = new Map(), groups = [];
    for (let r = 0; r < this.runs.length; r++) {
      let joins = null;
      if (passOfRun[r] > 0) {
        const mine = bars(r);
        for (let e = r - 1; e >= 0; e--) {
          if (passOfRun[e] === passOfRun[r] - 1 && [...bars(e)].some((b) => mine.has(b))) { joins = sectionOfRun.get(e); break; }
        }
      }
      if (joins === null) { groups.push([r]); sectionOfRun.set(r, groups.length - 1); }
      else { groups[joins].push(r); sectionOfRun.set(r, joins); }
    }
    this.sections = groups.map((g) => {
      const printed = this.runs[g[0]].map((id) => LiveJudge.bar(this.byId.get(id)));
      const first = Math.min(...printed), last = Math.max(...printed);
      return { firstBar: first, lastBar: last, times: g.map((r) => this.runs[r]),
        bars: first === last ? `Bar ${first}` : `Bars ${first}–${last}` };
    });
  }

  /** The notes of a repeat the player has just reached, once per run; null otherwise. */
  repeatStarting() {
    const id = this.next();
    if (id == null) return null;
    const run = this.runOf.get(id);
    if (this.byId.get(id).pass === 0 || this.announced.has(run)) return null;
    this.announced.add(run);
    return this.runs[run];
  }

  /** One batch from the engine. Returns {marks: Map, played: [ids]}. */
  add(batch, now = performance.now()) {
    const marks = new Map(), played = [];
    for (const e of batch) {
      const start = e.start_time_ms;
      if (start == null) continue;
      const id = e.note_id;
      if (id === 0) {
        if (e.end_time_ms == null) this.stray(midiOf(e.pitch_hz), start, marks);
        continue;
      }
      const note = this.byId.get(id);
      if (!note || this.heard.has(id) || note.startMs < this.fromMs) continue;
      this.onset(note, start, marks);
      played.push(id);
      this.lastStartMs = Math.max(this.lastStartMs ?? note.startMs, note.startMs);
      this.lastHeardAt = now;
    }
    return { marks, played };
  }

  onset(note, heardMs, out) {
    const id = note.noteId;
    this.heard.add(id);
    const stray = this.strays.get(id);
    if (!(stray && stray[0] < heardMs - CORRECTED_AFTER_MS)) this.set(id, this.timing(note, heardMs - note.startMs), out);
    for (const n of this.notes) {
      if (n.startMs >= note.startMs - MISSED_AFTER_MS) break;
      if (n.startMs < this.fromMs || n.grace || this.heard.has(n.noteId) || this.marks.has(n.noteId)) continue;
      this.set(n.noteId, { result: Result.missed }, out);
    }
  }

  timing(note, offMs) {
    if (Math.abs(offMs) <= this.perfectMs()) return { result: Result.perfect, offMs };
    if (Math.abs(offMs) <= this.closeMs(note)) return { result: Result.close, offMs };
    return { result: offMs < 0 ? Result.early : Result.late, offMs };
  }

  stray(playedMidi, atMs, out) {
    let target = null, best = Infinity;
    for (const n of this.notes) {
      if (n.startMs > atMs + STRAY_REACH_MS) break;
      if (n.startMs < Math.max(this.fromMs, atMs - STRAY_REACH_MS) || n.grace || this.heard.has(n.noteId) || this.marks.has(n.noteId)) continue;
      const distance = Math.abs(n.startMs - atMs) + 10 * Math.abs(n.midi - playedMidi);
      if (distance < best) { best = distance; target = n; }
    }
    if (!target || this.strays.has(target.noteId)) return;
    this.strays.set(target.noteId, [atMs, playedMidi]);
    this.set(target.noteId, { result: Result.wrong, playedMidi }, out);
  }

  /** Starts over from `noteId` (the first note when null). Returns {cleared, due, showPass}. */
  restartFrom(noteId) {
    const from = noteId == null ? null : this.byId.get(noteId);
    this.fromMs = from ? from.startMs : -Infinity;
    const cleared = [];
    for (const n of this.notes) {
      if (n.startMs < this.fromMs) continue;
      if (this.marks.delete(n.noteId)) cleared.push(n.noteId);
      this.heard.delete(n.noteId);
      this.strays.delete(n.noteId);
    }
    this.lastStartMs = null; this.lastHeardAt = null; this.dueIds = [];
    let showPass = null;
    if (!from) this.announced.clear();
    else {
      const run = this.runOf.get(from.noteId);
      for (const r of [...this.announced]) if (r >= run) this.announced.delete(r);
      if (from.pass > 0 && this.runs[run][0] !== from.noteId) { this.announced.add(run); showPass = this.runs[run]; }
    }
    return { cleared, due: this.due(), showPass };
  }

  /** The notes to play now, or null when unchanged since the last call. */
  due(now = performance.now()) {
    const first = this.notes.find((n) => this.open(n));
    const result = [];
    if (first) {
      let reach = first.startMs;
      if (this.lastStartMs != null && this.lastHeardAt != null) {
        const since = now - this.lastHeardAt + REPORT_LAG_MS;
        reach = Math.max(reach, this.lastStartMs + Math.min(since, MAX_RUN_ON_MS));
      }
      for (const n of this.notes) {
        if (n.startMs < first.startMs) continue;
        if (n.startMs > reach + CHORD_MS) break;
        if (this.open(n)) result.push(n.noteId);
      }
    }
    if (result.length === this.dueIds.length && result.every((id, i) => id === this.dueIds[i])) return null;
    this.dueIds = result;
    return result;
  }

  next() { const n = this.notes.find((m) => this.open(m)); return n ? n.noteId : null; }
  open(n) { return n.startMs >= this.fromMs && !n.grace && !this.heard.has(n.noteId) && !this.marks.has(n.noteId); }

  counts() {
    const c = Object.fromEntries(Object.values(Result).map((r) => [r, 0]));
    for (const v of this.marks.values()) c[v.result]++;
    return c;
  }

  /** 0-100 for what was played (ScoreSummarySheet.score). */
  score() {
    const c = this.counts(), total = Object.values(c).reduce((a, b) => a + b, 0);
    return total ? Math.round((c.perfect + 0.75 * c.close) / total * 100) : 0;
  }

  /** One line about a note's verdict (NoteVerdict.describe). */
  describe(id) {
    const n = this.byId.get(id), v = this.marks.get(id), name = noteName(n.midi);
    const ms = v.offMs != null ? Math.round(Math.abs(v.offMs)) : null;
    switch (v.result) {
      case Result.perfect: return `${name} · on time`;
      case Result.close: return `${name} · a little ${v.offMs < 0 ? 'early' : 'late'} (${ms} ms)`;
      case Result.early: return `${name} came early by ${ms} ms`;
      case Result.late: return `${name} came late by ${ms} ms`;
      case Result.wrong: return `Played ${noteName(v.playedMidi ?? n.midi)} instead of ${name}`;
      default: return `${name} was not played`;
    }
  }

  set(id, verdict, changed) {
    const old = this.marks.get(id);
    if (old && old.result === verdict.result && old.playedMidi === verdict.playedMidi && old.offMs === verdict.offMs) return;
    this.marks.set(id, verdict);
    changed.set(id, verdict);
  }
}

export function timeName(i) {
  const n = i + 1, suffix = n % 100 >= 11 && n % 100 <= 13 ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' })[n % 10] ?? 'th';
  return `${n}${suffix} time`;
}
