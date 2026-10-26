# API Routes

Root URLconf: `backend/server/urls.py`, which includes `api.urls`,
`scores.urls`, `guidelines.urls`, `hum.urls` and `User_accounts.urls`.
Bodies are JSON; POST views are CSRF-exempt. In production every request
also needs the `X-App-Key` header (`server/middleware.py`).

## Current routes

| Method | Path | View | Auth |
|---|---|---|---|
| POST | `/developer/chat/` | `api.views.chat_view` | — |
| POST | `/api/feedback/phrase` | `api.views.phrase_feedback_view` | — |
| POST | `/api/feedback/summary` | `api.views.summary_feedback_view` | — |
| GET | `/api/quiz/topics`, POST `/api/quiz/generate` | `quiz.api` | — |
| GET | `/api/scores/search` | `scores.views.search_view` | — |
| GET | `/api/scores/<id>/musicxml` | `scores.views.musicxml_view` | — |
| PATCH | `/api/scores/<id>/tags` | `guidelines.views.score_tags_view` | author |
| GET | `/api/guidelines` | `guidelines.views.guidelines_view` | optional |
| POST | `/api/guidelines` | `guidelines.views.guidelines_view` | author |
| GET | `/api/guidelines/<id>` | `guidelines.views.guideline_view` | optional |
| PUT/DELETE | `/api/guidelines/<id>` | `guidelines.views.guideline_view` | owner or admin |
| GET | `/api/guidelines/for-score/<score_id>` | `guidelines.views.for_score_view` | — |
| GET | `/api/guidelines/tags` | `guidelines.views.tags_view` | — |
| GET | `/api/guidelines/vocabulary` | `guidelines.views.vocabulary_view` | — |
| POST | `/api/guidelines/rubrics/parse` | `guidelines.views.parse_rubric_view` | author |
| * | `/api/auth/*` | `User_accounts.views` | see that module |
| * | `/api/hum/*` | `hum` views | — |

"author" = a bearer token of an admin (`is_staff`) or a verified
contributor (group `guideline_contributor`; grant it with
`python manage.py guideline_contributor add <email>`). Others get 401
(no/invalid token) or 403. `/api/auth/me` returns the user's `roles`.

## Feedback

`/api/feedback/phrase` and `/api/feedback/summary` are documented in their
docstrings and in `practice_hub/feedback_generator/README.md`. A phrase's
`piece` may carry `score_id` (int) and/or `tags` ([str]); the published
guidelines sharing any tag are checked too, adding `category: "guideline"`
findings, `scores.guidelines` (never part of `overall`) and
`guidelines_applied`. The summary adds a `Guidelines` section.

## Guidelines

- **Guideline JSON:** `{id, title, body, tags, status: draft|published,
  visibility, version, owner_name, editable, created_at, updated_at,
  rubrics: [...]}`.
- **Rubric JSON:** `{id, label, source_text, metric, operator, value,
  value_max, unit, applies_to, pass_rate, severity, fail_message,
  suggestion, enabled}`. `metric`/`unit` come from `GET /api/guidelines/vocabulary`.
- **GET `/api/guidelines`:** published public guidelines.
  - With an author token, `?mine=1` gives your own, drafts included.
  - With an author token, `?all=1` adds your own drafts; for admins it gives everything.
  - `?tags=a,b` filters by tag.
- **POST / PUT:** the body is the guideline fields above, plus nested `rubrics`.
  - PUT updates only the fields sent. A rubric sent with its `id` keeps it; rubrics left out are deleted.
  - Each edit bumps `version`.
  - Invalid input returns 400 `{error, code: "invalid", fields: {...}}`.
  - Limits: title ≤ 200, body ≤ 20 000, ≤ 20 tags, ≤ 20 rubrics. Only `visibility: public` is accepted for now.
- **POST `/api/guidelines/rubrics/parse`:** `{text}` →
  `{rule|null, matched_spans: [{start, end, role}], missing, unrecognised, message, translator}`.
  - `"gaps between the notes is more then 0.5 sec"` →
    `{metric: note_gap, operator: gt, value: 0.5, unit: sec}`.
- **PATCH `/api/scores/<id>/tags`:** `{tags?, composed_date?}`.
  - The era tag (from `composed_date`) and the composer tag are kept in sync automatically.

## Legacy (no longer routed)

The sections below describe IMSLP/OMR endpoints that `api/urls.py` no
longer includes. Kept for reference.

## POST `/developer/chat/`
Dev/debug echo endpoint.

**Body:** `{"prompt": "..."}`
**Response:** `{"response": "<prompt echoed back>"}`
**Errors:** 400 if `prompt` missing/blank or body isn't valid JSON.

## POST `/developer/api/search`
Dev/debug IMSLP search (thin wrapper, superseded by `/api/imslp/search`).

**Body:** `{"query": "..."}`
**Response:** `{"query": "...", "results": [...]}`
**Errors:** 400 if `query` missing/blank or invalid JSON.

## POST `/api/imslp/search`
Look up a work's available versions/editions on IMSLP (cached in the DB
after the first lookup). A bare composer name returns that composer's
full work list; anything more specific resolves to the top search hit.

**Body:** `{"query": "...", "url": "<optional IMSLP work URL>"}`
(`url` skips the IMSLP search call and looks up that exact page directly.)
**Response:** `{"title", "composer", "imslp_url", "choices": [{"id", "name", "instrumentation", "type", "imslp_url", "movement", "arranger", "editor", "file_name"}, ...]}`
**Errors:** 400 invalid JSON / missing query+url, 404 work not found, 502 IMSLP network error.

## POST `/api/imslp/download`
Download a specific score version/edition from IMSLP into permanent
storage (drives a real browser through IMSLP's disclaimer/subscribe
flow). Returns the existing file immediately if already downloaded.

**Body:** `{"score_id": "...", "imslp_url": "..."}`
**Response:** `{"status": "completed"|"failed", "score_id": "...", "file_path": "storage/scores/<Composer>/<Work>/<file>.pdf", "error": "..."}`
`file_path` is the canonical identifier passed to the two `/api/score/*` endpoints below.
**Errors:** 400 missing score_id / invalid IMSLP URL, 502 browser/download failure, 503 IMSLP subscription-gated, 500 file save failure.

## POST `/api/score/process`
Convert a stored score PDF into a notes JSON using `backend/processor`
(a hand-built, non-ML OMR heuristic), optionally with a debug PDF
showing every detected note circled and pitch-labeled on the original
score.

**Body:** `{"file_path": "storage/scores/...", "bpm": 120, "debug_pdf": true}`
**Response:** `{"file_path", "json_path", "note_count", "debug_pdf_path"?}`
**Errors:** 400 missing file_path / invalid JSON, 404 file not found, 500 processing error.

## POST `/api/score/process-omr`
Convert a stored score PDF into notes JSON using `backend/practice_hub/pdf_processor`
(the oemer ML-based OMR pipeline): splits the PDF into per-page PNGs,
runs OMR to MusicXML with a debug PNG per page (every detected
notehead/clef/barline/etc. boxed and labeled), then parses timed note
events. All output files are written next to the source PDF in storage.

**Body:** `{"file_path": "storage/scores/..."}`
**Response:**
```json
{
  "file_path": "storage/scores/...",
  "pages": ["storage/scores/.../page-001.png", ...],
  "musicxml": ["storage/scores/.../page-001.musicxml", ...],
  "debug_png": ["storage/scores/.../page-001_debug.png", ...],
  "notes_json": ["storage/scores/.../page-001_notes.json", ...],
  "bpm": 120,
  "time_signature": "4/4",
  "note_count": 296,
  "timing": {"split": 0.13, "omr": 199.56, "notes": 0.09, "total": 199.78}
}
```
**Errors:** 400 missing file_path / invalid JSON, 404 file not found, 500 processing error.

Note: this and `/api/score/process` are two independent OMR pipelines
(ML-based vs. heuristic-based) kept side by side in the codebase — see
`backend/practice_hub/pdf_processor/README.md` and `backend/processor/processor.py`.
