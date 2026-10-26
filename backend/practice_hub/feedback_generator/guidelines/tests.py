"""Run explicitly (feedback_generator isn't an installed app):

    cd backend
    python manage.py test practice_hub.feedback_generator.guidelines.tests
"""

import json
from pathlib import Path

from django.test import SimpleTestCase

from ..judges import ExpectedNote, PhraseContext, UserNote, beats_per_bar
from ..orchestrator import _parse_expected_note, _parse_user_note, align_notes
from . import METRICS, GuidelineSpec, RubricSpec, evaluate_guidelines, evaluate_rubric

SAMPLE = Path(__file__).resolve().parent.parent / "sample_data" / "phrase_imperfect.json"


def phrase(bpm, played_fraction, count=4, markings=None, volumes=None, skip=()):
    """`count` back-to-back quarter notes at `bpm`, each played for
    `played_fraction` of its written length, on time."""
    beat = 60000.0 / bpm
    expected, user = [], []
    for i in range(count):
        start = i * beat
        expected.append(
            ExpectedNote(
                note_id=i + 1, pitch_hz=440.0, start_time_ms=start, end_time_ms=start + beat,
                duration_ms=beat, markings=markings,
            )
        )
        if i in skip:
            continue
        played = beat * played_fraction
        user.append(
            UserNote(
                pitch_hz=440.0, start_time_ms=start, end_time_ms=start + played, duration_ms=played,
                note_id=i + 1, volume=(volumes[i] if volumes else None),
            )
        )
    matched, missing, extra = align_notes(expected, user, bpm)
    return PhraseContext(
        phrase=1, bpm=bpm, beats_per_bar=4, matched=matched, missing=missing, extra=extra
    )


def guideline(*rubrics):
    return GuidelineSpec(id=7, title="Baroque: detached touch", version=3, rubrics=tuple(rubrics))


def gap_rubric(**kwargs):
    defaults = dict(id=11, metric="note_gap", operator="gt", value=0.5, unit="sec")
    defaults.update(kwargs)
    return RubricSpec(**defaults)


class GuidelineMetricTests(SimpleTestCase):
    def test_note_gap_measures_release_to_next_attack(self):
        ctx = phrase(60, 0.4)  # 1000 ms beats, 400 ms played -> 600 ms gaps
        values = [m.value for m in METRICS["note_gap"].measure(ctx, "all")]
        self.assertEqual(len(values), 3)
        for value in values:
            self.assertAlmostEqual(value, 600.0)

    def test_note_gap_skips_pairs_with_a_missing_note(self):
        ctx = phrase(60, 0.4, count=3, skip=(1,))
        self.assertEqual(METRICS["note_gap"].measure(ctx, "all"), [])

    def test_sounding_ratio(self):
        ctx = phrase(120, 0.5)
        values = [m.value for m in METRICS["sounding_ratio"].measure(ctx, "all")]
        self.assertEqual(values, [0.5] * 4)

    def test_volume_range_none_without_volumes(self):
        self.assertEqual(METRICS["volume_range"].measure(phrase(120, 1.0), "all"), [])

    def test_volume_range_with_volumes(self):
        ctx = phrase(120, 1.0, volumes=[0.4, 0.6, 0.5, 0.7])
        (measurement,) = METRICS["volume_range"].measure(ctx, "all")
        self.assertAlmostEqual(measurement.value, 0.3)

    def test_applies_to_filters_on_markings(self):
        self.assertEqual(METRICS["sounding_ratio"].measure(phrase(120, 0.5), "staccato"), [])
        marked = phrase(120, 0.5, markings="staccato")
        self.assertEqual(len(METRICS["sounding_ratio"].measure(marked, "staccato")), 4)
        self.assertEqual(METRICS["sounding_ratio"].measure(marked, "unmarked"), [])


class GuidelineEvaluatorTests(SimpleTestCase):
    def test_absolute_gap_passes_at_slow_tempo(self):
        score, findings = evaluate_guidelines(phrase(60, 0.4), [guideline(gap_rubric())])
        self.assertEqual(score, 100)
        self.assertEqual(findings, [])

    def test_absolute_gap_fails_at_fast_tempo_but_relative_passes(self):
        fast = phrase(160, 0.5)  # 375 ms beats, 187.5 ms gaps
        score, findings = evaluate_guidelines(fast, [guideline(gap_rubric())])
        self.assertEqual(score, 0)
        (finding,) = findings
        self.assertEqual(finding.category, "guideline")
        self.assertEqual(finding.details["guideline_id"], 7)
        self.assertEqual(finding.details["rubric_id"], 11)
        self.assertEqual(finding.details["version"], 3)
        self.assertEqual(finding.details["issue"], "rubric:11")
        self.assertEqual(finding.details["measured_pass_rate"], 0.0)
        self.assertEqual(finding.bars, 1)

        relative = gap_rubric(operator="gte", value=30, unit="pct_of_note")
        score, findings = evaluate_guidelines(fast, [guideline(relative)])
        self.assertEqual((score, findings), (100, []))

    def test_gte_and_between_include_their_edges(self):
        ctx = phrase(60, 0.8)  # 200 ms gaps
        for rubric in (
            gap_rubric(operator="gte", value=200, unit="ms"),
            gap_rubric(operator="lte", value=0.2, unit="sec"),
            gap_rubric(operator="between", value=0.2, value_max=0.4, unit="sec"),
            gap_rubric(operator="gte", value=20, unit="pct_of_beat"),
        ):
            with self.subTest(rubric=rubric):
                self.assertEqual(evaluate_rubric(ctx, guideline(rubric), rubric), (1.0, None))
        strict = gap_rubric(operator="gt", value=200, unit="ms")
        measured, finding = evaluate_rubric(ctx, guideline(strict), strict)
        self.assertEqual(measured, 0.0)
        self.assertIsNotNone(finding)

    def test_pass_rate_threshold(self):
        # 3 gaps, one clipped short: 2/3 pass.
        ctx = phrase(60, 0.4)
        first_user = ctx.matched[0][1]
        first_user.end_time_ms = first_user.start_time_ms + 900
        lenient = gap_rubric(pass_rate=0.6)
        strict = gap_rubric(pass_rate=0.8)
        self.assertIsNone(evaluate_rubric(ctx, guideline(lenient), lenient)[1])
        self.assertIsNotNone(evaluate_rubric(ctx, guideline(strict), strict)[1])

    def test_nothing_to_measure_is_null_and_silent(self):
        one_note = phrase(60, 0.4, count=1)
        self.assertEqual(evaluate_guidelines(one_note, [guideline(gap_rubric())]), (None, []))
        empty = PhraseContext(phrase=1, bpm=60, beats_per_bar=4, matched=[], missing=[], extra=[])
        self.assertEqual(evaluate_guidelines(empty, [guideline(gap_rubric())]), (None, []))
        self.assertEqual(evaluate_guidelines(one_note, []), (None, []))

    def test_tutorial_only_guideline_produces_nothing(self):
        self.assertEqual(evaluate_guidelines(phrase(60, 0.4), [guideline()]), (None, []))

    def test_custom_message_and_suggestion(self):
        rubric = gap_rubric(fail_message="Detach more.", suggestion="Lift between notes.", severity="major")
        _, (finding,) = evaluate_guidelines(phrase(160, 1.0), [guideline(rubric)])
        self.assertEqual(finding.message, "Detach more.")
        self.assertEqual(finding.severity, "major")
        self.assertEqual(finding.details["suggestion"], "Lift between notes.")

    def test_sample_phrase(self):
        """The demo: the imperfect sample against "gap >= 30% of the note"."""
        body = json.loads(SAMPLE.read_text())
        bpm = body["timing"]["bpm"]
        expected = [_parse_expected_note(n) for n in body["expected_notes"]]
        user = [_parse_user_note(n) for n in body["user_notes"]]
        matched, missing, extra = align_notes(expected, user, bpm)
        ctx = PhraseContext(
            phrase=1, bpm=bpm, beats_per_bar=beats_per_bar("4/4"), matched=matched, missing=missing, extra=extra
        )
        rubric = gap_rubric(operator="gte", value=30, unit="pct_of_note")
        measured, finding = evaluate_rubric(ctx, guideline(rubric), rubric)
        # The sample is played legato, so the detached-touch rubric fails.
        self.assertIsNotNone(measured)
        self.assertLess(measured, 0.8)
        self.assertTrue(finding.details["failing_bars"])
