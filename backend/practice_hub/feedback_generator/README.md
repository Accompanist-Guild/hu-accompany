Feedback generation, in two phases: phase 1 judges one phrase at a time,
phase 2 summarizes the whole session.

Run everything from `backend/` with `DYLD_LIBRARY_PATH=/opt/homebrew/lib`
(libvips isn't on the default linker path on macOS).

## 1. Layout

```
feedback_generator/
  orchestrator.py   wiring only -- parse, align, call judges, return dicts
  summarizer.py     phase 2 -- aggregates every phrase into one summary
  store.py          reads/writes storage/feedback/
  errors.py
  bar_boxes/        pixel box per bar for the score highlight (own README)
  judges/           all feedback text and all 0-100 ratings live here
    __init__.py     shared notes/context/Finding types, pitch + bar math,
                    thresholds, judge registry
    feedbacks.py    every message + suggestion a judge can emit
    phase1/         one phrase at a time
      __init__.py     JUDGES = run order
      pitch.py        intonation, wrong notes
      rhythm.py       note onsets (early/late) and note lengths
      tempo.py        pulse drift across a phrase
      articulation.py staccato / legato / marcato vs. markings
      notes.py        notes not played, notes not written
      dynamics.py     loudness from user notes' `volume` vs. written dynamics
      pedaling.py     no pedal data upstream -- scores null, says nothing
    phase2/         the whole session at once
      __init__.py     JUDGES = run order
      era.py          style-period performance practice
```

- Each judge owns one dimension: its detection and its rating. Its wording
  lives in `judges/feedbacks.py`, which the judge imports -- reword there,
  not in the judge.
- Judge contract, same in both phases: `NAME`, `PHASE` (1 or 2),
  `judge(ctx) -> JudgeResult`. Phase 1 gets a `PhraseContext` (that phrase's
  aligned notes), phase 2 a `PieceContext` (every stored phrase, aggregated
  scores, every finding).
- Nothing outside `judges/` writes feedback text; nothing outside
  `summarizer.py` aggregates across phrases.
- Adding a dimension = one new file in `judges/phase1/` or `judges/phase2/`
  + one entry in that package's `JUDGES` + its text in `judges/feedbacks.py`.

## 2. Storage

```
storage/feedback/<date>-<piece>/       e.g. 2026-09-07-Prelude_in_C
  Phase1/
    Phrase1.json    one file per phrase
    Phrase2.json
  Phase2/
    Summary.json    summarizer.py
    Era.json        judges/phase2/era.py
```

- No DB table -- JSON on disk, like `pdf_processor`'s piece_data.
- Session directory defaults to today's date + the piece title, so phrases
  of one piece group themselves; pass `session_id` to target one explicitly.
- Phrases are 1-based, and re-sending a phrase overwrites just that file.
- Phase 2 is re-runnable: each run overwrites `Phase2/` with a snapshot of
  every phrase stored so far.
- Piece metadata (title/composer/composed_date) is stored in each phase-1
  file header; phase 2 reads it back from there.

Phase-1 file:

```json
{"piece": {...}, "recorded_at": "...", "phrase": 1, "bpm": 96.0,
 "time_signature": "4/4", "bars": [1, 4],
 "scores": {"overall": 85, "pitch": 79, "rhythm": 92, "tempo": null,
            "dynamics": null, "articulation": null},
 "feedback": [{"bars": 1,
               "box": {"page": 1, "x": 412, "y": 903, "w": 305, "h": 330,
                       "page_size": [2262, 3200]},
               "category": "pitch", "severity": "major",
               "confidence": 1.0, "message": "...", "details": {...}}]}
```

- `feedback` is the unit everywhere -- phase 2 uses the same shape.
- `bars` on a finding = the bar it happened in: the bar the score prints when
  every expected note carries `bar` (the app sends it for scores, so a pickup
  bar or a followed tempo can't shift it), otherwise numbered from the piece
  start using `bpm` + `time_signature`; `bars` on the file = the span.
- Alignment trusts a user note's `note_id` first (within the timing window),
  for every note, before pairing the rest by time and pitch: an unplayed note
  can't take its neighbour's detection, and a wrong key (no `note_id`) is
  paired with the note it replaced, so it reads as a wrong note rather than a
  missing one plus an extra one.
- `box` is that same bar as a pixel rectangle on the score, so the app can
  mark the spot instead of making the player count bars. It comes from
  `pdf_processor`'s `<Piece>_bars.json`, passed in as `judge_phrase`'s
  `bar_boxes` (`/api/feedback/phrase`'s `bar_boxes`); without it every
  `box` is `null`. Pixels are measured on the page PNG whose dimensions
  `page_size` gives, so a client rendering the PDF at another resolution
  scales by its own width/height. Phase 2's summary findings carry
  `details.boxes` -- every bar box behind that recurring problem.
- `severity` is `minor`/`major`; `confidence` is 0.5 at the "this is an
  error" threshold, rising to 1.0 for an unmistakable one.
- `details` carries the numbers behind the call (cents, ms, ratio) plus a
  `suggestion`.
- A `null` score means that judge had nothing to measure, and it drops out
  of `overall` instead of counting as zero. `pedaling` is always null: no
  note schema upstream (mobile app / native_ffi / pdf_processor) carries
  pedal events. `dynamics` is null only when no user note carries a
  `volume` (native_ffi's 0-1 dB-spaced loudness, see
  `rust_samples/README.md`).
- Dynamics only compares notes within the phrase, because `volume` depends
  on the device: written level changes (p -> f) and cresc./dim. must move
  the right way, accents (`has_accent`, sf/sfz/fp) must stand out, and any
  other note must stay near the level around it. Levels come from
  `markings` and carry forward until the next one. Findings carry
  `details.issue` = `contrast` / `hairpin` / `accent` / `evenness`, plus
  `change_db`.

## 3. Quick test

```
python manage.py test practice_hub.feedback_generator.tests api.tests -v 2
```

- 77 tests, no server needed.
- Writes nothing into `backend/storage/` — `STORAGE_ROOT` points at a temp dir.

## 4. Debug test to storage

```
python manage.py runserver 0.0.0.0:8000
```

Phase 1 — POST one phrase (the same request the app sends,
`frontend/lib/Send_Strings_2Server.dart`):

```
curl -s -X POST http://127.0.0.1:8000/api/feedback/phrase \
  -H "Content-Type: application/json" \
  -d '{
    "phrase": 1,
    "timing": {"bpm": 96, "time_signature": "4/4"},
    "piece": {"title": "Prelude in C", "composer": "Bach", "composed_date": "1722"},
    "expected_notes": [
      {"note_id": 1, "pitch_hz": 261.63, "start_time_ms": 0,   "end_time_ms": 625,  "duration_ms": 625},
      {"note_id": 2, "pitch_hz": 293.66, "start_time_ms": 625, "end_time_ms": 1250, "duration_ms": 625}
    ],
    "user_notes": [
      {"note_id": 1, "pitch_hz": 261.63, "start_time_ms": 0,   "end_time_ms": 625,  "duration_ms": 625},
      {"note_id": 2, "pitch_hz": 277.18, "start_time_ms": 765, "end_time_ms": 1390, "duration_ms": 625}
    ]
  }' | python -m json.tool
```

- Note 2 is a semitone flat and 140 ms late, so there's something to say;
  `expected_notes` must be non-empty, `user_notes` may be (silence -> every
  note comes back missing).
- The response ends with what it wrote:

```
    "session_id": "2026-09-07-Prelude_in_C",
    "stored_at": "storage/feedback/2026-09-07-Prelude_in_C/Phase1/Phrase1.json"
```

- Send `"phrase": 2` with the same `session_id` for the next phrase; reuse a
  phrase number to overwrite that take.
- Use the LAN address (`ipconfig getifaddr en0`) to test from the phone.

Phase 2 — summarize everything stored for that session:

```
curl -s -X POST http://127.0.0.1:8000/api/feedback/summary \
  -H "Content-Type: application/json" \
  -d '{"session_id": "2026-09-07-Prelude_in_C"}' | python -m json.tool
```

- Writes `Phase2/Summary.json` (piece-wide scores, top 3 recurring
  problems, what went well, one-line summary), `Phase2/Era.json` and
  `Phase2/Guidelines.json` (authored-guideline adherence, §6).
- 404 if the session has no phase-1 phrases yet.
- `backend/storage/` is **not** gitignored — clean up with
  `rm -r storage/feedback`.

## 5. `judges/phase2/era.py` status
- Detection only. Date parsing, era detection and the per-era trait tables
  work. `Era.json` has `era`/`label`/`traits`, a one-line `summary`
  ("Composed in the Baroque era.") and `feedback: []`.
- Era-specific feedback is authored as guidelines tagged with the era (§6).
```
python -c "
from practice_hub.feedback_generator.judges.phase2.era import parse_composed_year, detect_era, adjacent_era
for d in [1722, '1810', 'ca. 1785', '1830s', '1802-1804', '18th century', None, 'unknown']:
    y = parse_composed_year(d); e = detect_era(d); a = adjacent_era(y)
    print(repr(d), '->', y, e.label if e else None, '| adjacent:', a.label if a else None)
"
```

- Expect `1722 -> 1722 Baroque`, `'1810' -> 1810 Classical | adjacent: Romantic`
  (within `TRANSITION_MARGIN_YEARS` of 1820), `'1830s' -> 1835`,
  `'1802-1804' -> 1803` (midpoint), `'18th century' -> 1750`.
- `None`/`''`/`'unknown' -> None None`, i.e. the era section stays empty.
- Once the builders produce prose, extend `EraDetectionTests`/`JudgePieceTests`
  in `tests.py` with the boundary years (1749/1750, 1819/1820).

## 6. Authored guidelines (`guidelines/`)

Admins and verified contributors write guidelines in the app's Guides tab
(Django app `backend/guidelines`). Each guideline is "how to play" text
attached to tags (`baroque`, `j-s-bach`, `fugue`) and may carry rubrics:
measurable rules checked on every phrase **in addition to** the built-in
judges. They never change `overall`.

- `guidelines/types.py`: `RubricSpec` / `GuidelineSpec`. These are framework-free; the ORM converts to them with `to_spec()`.
- `guidelines/metrics.py` holds the metric registry. Each metric turns a `PhraseContext` into measurements:
  - `note_gap`: the next played onset minus this played offset, for written notes that touch and were both played. Units: `ms`, `sec`, `pct_of_note`, `pct_of_beat`.
  - `sounding_ratio`: played length divided by written length. Units: `pct_of_note`, `ratio`.
  - `onset_deviation`: how far each onset was from the written one, in ms. Units: `ms`, `sec`, `pct_of_beat`.
  - `volume_range`: loudest minus softest note in the phrase. Units: `volume` (0–1), `db`.
  - `applies_to` (`all|staccato|legato|unmarked`) filters on `markings`.
- `guidelines/evaluator.py` checks the rubrics:
  - A rubric fails when the share of passing measurements is below `pass_rate` (default 0.8).
  - Relative units are resolved per note and tempo. For example, 30% of the note on a 375 ms quarter at ♩=160 is 112.5 ms.
  - Nothing to measure means no finding, and the rubric doesn't count towards the guideline score.
- **Phase 1:**
  - `judge_phrase(..., guidelines=[GuidelineSpec])` adds `category: "guideline"` findings, with details `{guideline_id, guideline_title, version, rubric_id, metric, pass_rate, measured_pass_rate, checked, failed, failing_bars, suggestion}`.
  - It also adds `scores.guidelines`, the mean pass rate × 100 or null.
  - `guidelines_applied: [{id, version, title}]` is stored in the phrase file.
  - The API resolves the guidelines from `piece.score_id` / `piece.tags`.
- **Phase 2:**
  - `judges/phase2/guidelines.py` writes `Phase2/Guidelines.json` with `{guidelines: [{id, version, title, phrases_checked}], rubrics: [{..., phrases_checked, phrases_failed, worst_bars, suggestion}], feedback: [...]}`.
  - The summarizer leaves guideline findings out of `Summary.json`'s top problems.
- Rubric text is parsed by `backend/guidelines/parsing/` (a keyword vocabulary in `vocab.py`, behind a `RubricTranslator` interface).

Tests:
`python manage.py test practice_hub.feedback_generator.guidelines.tests guidelines`.
