#!/usr/bin/env python3
"""Render a practice run of a real score, mistakes and all, for examples/practice.rs.

The score's notes come from the app's own reader (score_timeline.js, through
score_to_timeline.js). The "player" keeps a slower tempo than written, drifts
around it, pauses once, plays a few wrong keys (a semitone or a tone off) and
skips a few notes. truth.json says which, so the detector can be scored:

  node fixtures/piano/score_to_timeline.js score.musicxml /tmp/elise.json
  python3 fixtures/piano/perform.py /tmp/elise.json /tmp/run --seconds 45 --tempo 0.85
  cargo run --release --example practice -- /tmp/run/performance.wav /tmp/run/piece.json --truth /tmp/run/truth.json

Writes <out>/{piece.json, truth.json, performance.mid, performance.wav}. Needs
mido, numpy and the fluidsynth CLI; the soundfont defaults to the FluidR3 copy
the hum feature uses.
"""
import argparse, json, math, random, subprocess, wave
from pathlib import Path
import mido
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("timeline"); ap.add_argument("out")
ap.add_argument("--seconds", type=float, default=45)
ap.add_argument("--tempo", type=float, default=0.85, help="share of the written tempo the player keeps")
ap.add_argument("--rubato", type=float, default=0.04)
ap.add_argument("--pause-at", type=float, default=20000, help="score ms")
ap.add_argument("--pause-ms", type=float, default=2000)
ap.add_argument("--wrong", type=int, default=5)
ap.add_argument("--skip", type=int, default=2)
ap.add_argument("--noise-db", type=float, default=-50)
ap.add_argument("--seed", type=int, default=7)
ap.add_argument("--sf2", default=str(Path(__file__).resolve().parents[3] / "backend/hum/engine/accompanist/soundfonts/FluidR3_GM.sf2"))
a = ap.parse_args()
random.seed(a.seed)
out = Path(a.out); out.mkdir(parents=True, exist_ok=True)

t = json.load(open(a.timeline))
notes = [n for n in t["notes"] if n["startMs"] < a.seconds * 1000]

def perf_ms(s):
    """Score ms -> performance ms: slower than written, breathing, one pause."""
    p = s / a.tempo
    p += a.rubato * 4000 * math.sin(2 * math.pi * s / 9000)  # +-4% wander over ~9 s
    if s >= a.pause_at:
        p += a.pause_ms
    return p + 400  # the player starts 0.4 s after the mic opens

candidates = [n for n in notes[8:] if n["staff"] == 0 and not n["grace"] and n["durationMs"] < 600]
wrong = random.sample(candidates, a.wrong)
wrong_ids = {n["id"] for n in wrong}
skip_pool = [n for n in notes[8:] if n["id"] not in wrong_ids and not n["grace"]]
skipped = {n["id"] for n in random.sample(skip_pool, a.skip)}
shifts = [-1, 2, -2, 1, -1, 1]
played_midi = {n["id"]: n["midi"] + shifts[i % len(shifts)] for i, n in enumerate(wrong)}

events = []
for n in notes:
    if n["id"] in skipped:
        continue
    on = perf_ms(n["startMs"]) + random.gauss(0, 10)
    off = perf_ms(n["startMs"] + n["durationMs"]) - 15
    vel = random.randint(72, 92) if n["staff"] == 0 else random.randint(55, 70)
    midi = played_midi.get(n["id"], n["midi"])
    events.append((on, 1, midi, vel)); events.append((max(on + 40, off), 0, midi, 0))
events.sort()

mid = mido.MidiFile(ticks_per_beat=480)
tr = mido.MidiTrack(); mid.tracks.append(tr)
tr.append(mido.MetaMessage("set_tempo", tempo=500000))  # 120 bpm: 1 tick = 500000/480 us
tr.append(mido.Message("program_change", program=0, time=0))
last = 0
for ms, on, midi, vel in events:
    tick = int(round(ms / (500 / 480)))
    tr.append(mido.Message("note_on" if on else "note_off", note=midi, velocity=vel, time=max(0, tick - last)))
    last = max(last, tick)
mid.save(out / "performance.mid")

wav = out / "performance.wav"
subprocess.run(["fluidsynth", "-ni", "-g", "0.8", "-r", "48000", "-F", str(wav), a.sf2, str(out / "performance.mid")], check=True, capture_output=True)
with wave.open(str(wav)) as w:
    frames = w.readframes(w.getnframes()); ch = w.getnchannels(); rate = w.getframerate()
audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32).reshape(-1, ch).mean(axis=1) / 32768
audio = audio + np.random.default_rng(1).normal(0, 10 ** (a.noise_db / 20), audio.shape).astype(np.float32)
with wave.open(str(wav), "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
    w.writeframes((np.clip(audio, -1, 1) * 32767).astype(np.int16).tobytes())

piece = {
    "piece_name": "Für Elise (first %.0f s)" % a.seconds, "curr_phase": 0, "instrument": None, "curr_music_phrase": 0,
    "timing": {"bpm": float(t["bpm"]), "beat_unit": 4}, "follow_tempo": True,
    "notes": [{"note_id": n["id"], "pitch_hz": 440 * 2 ** ((n["midi"] - 69) / 12), "start_time_ms": n["startMs"],
               "end_time_ms": n["startMs"] + n["durationMs"], "duration_ms": n["durationMs"], "is_end": False,
               "vibrato_depth": None, "pedal_action": None, "has_accent": None, "markings": None} for n in notes],
}
json.dump(piece, open(out / "piece.json", "w"))
json.dump({"wrong": [{"id": i, "played_midi": m} for i, m in played_midi.items()], "skipped": sorted(skipped),
           "played": [n["id"] for n in notes if n["id"] not in skipped and n["id"] not in wrong_ids]}, open(out / "truth.json", "w"))
print(f"{len(notes)} notes, {len(wrong)} wrong {sorted(wrong_ids)}, skipped {sorted(skipped)}, {len(audio)/rate:.1f} s at {rate} Hz")
