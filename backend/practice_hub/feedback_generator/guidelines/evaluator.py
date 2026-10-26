"""Checks authored rubrics against one phrase.

For every rubric of every applicable guideline: measure the phrase with the
rubric's metric, test each measurement against the rule, and fail the rubric
when fewer than `pass_rate` of them pass. A failing rubric is one Finding
(category "guideline"); a passing one is silent. A rubric with nothing to
measure (no note pairs, no volumes) is skipped entirely -- no finding, and it
doesn't count towards the guideline score.

The guideline score is never part of `overall` (overall_score only counts
OVERALL_WEIGHTS keys): it is advice layered on top of the built-in judges.
"""

from typing import Iterable, List, Optional, Tuple

from ..judges import Finding, PhraseContext, confidence_for
from .metrics import METRICS, Measurement, Metric, to_native
from .types import GuidelineSpec, RubricSpec

CATEGORY = "guideline"
# Shortfall below the pass rate at which a failure is reported with full
# confidence (0.5 at the threshold, 1.0 at 2x this).
CONFIDENT_SHORTFALL = 0.25
MAX_FAILING_BARS = 8


def _passes(rubric: RubricSpec, metric: Metric, measurement: Measurement, beat_ms: float) -> bool:
    value = measurement.value
    threshold = to_native(rubric.value, rubric.unit, metric, measurement, beat_ms)
    if rubric.operator == "gt":
        return value > threshold
    if rubric.operator == "gte":
        return value >= threshold
    if rubric.operator == "lt":
        return value < threshold
    if rubric.operator == "lte":
        return value <= threshold
    if rubric.operator == "between":
        upper = to_native(rubric.value_max, rubric.unit, metric, measurement, beat_ms)
        low, high = sorted((threshold, upper))
        return low <= value <= high
    raise ValueError(f"unknown operator {rubric.operator!r}")


def _default_message(guideline: GuidelineSpec, rubric: RubricSpec, metric: Metric, measured: float) -> str:
    label = rubric.label or metric.label
    return (
        f"{guideline.title}: {round(measured * 100)}% of {metric.noun} met "
        f"\u201c{label}\u201d (target {round(rubric.pass_rate * 100)}%)."
    )


def evaluate_rubric(
    ctx: PhraseContext, guideline: GuidelineSpec, rubric: RubricSpec
) -> Tuple[Optional[float], Optional[Finding]]:
    """(measured pass rate or None when nothing applied, Finding or None)."""
    metric = METRICS.get(rubric.metric)
    if metric is None:
        return None, None
    measurements = metric.measure(ctx, rubric.applies_to)
    if not measurements:
        return None, None

    failing = [m for m in measurements if not _passes(rubric, metric, m, ctx.beat_ms)]
    measured = (len(measurements) - len(failing)) / len(measurements)
    if measured >= rubric.pass_rate:
        return measured, None

    failing_bars = sorted({m.bar for m in failing})
    finding = Finding(
        bars=failing_bars[0] if failing_bars else 0,
        category=CATEGORY,
        severity=rubric.severity if rubric.severity in ("minor", "major") else "minor",
        confidence=confidence_for(rubric.pass_rate - measured, 0.0, CONFIDENT_SHORTFALL),
        message=rubric.fail_message or _default_message(guideline, rubric, metric, measured),
        details={
            "issue": f"rubric:{rubric.id}",
            "guideline_id": guideline.id,
            "guideline_title": guideline.title,
            "version": guideline.version,
            "rubric_id": rubric.id,
            "label": rubric.label or metric.label,
            "metric": rubric.metric,
            "pass_rate": rubric.pass_rate,
            "measured_pass_rate": round(measured, 3),
            "checked": len(measurements),
            "failed": len(failing),
            "failing_bars": failing_bars[:MAX_FAILING_BARS],
            "suggestion": rubric.suggestion,
        },
    )
    return measured, finding


def evaluate_guidelines(
    ctx: PhraseContext, guidelines: Iterable[GuidelineSpec]
) -> Tuple[Optional[int], List[Finding]]:
    """(0-100 guideline score or None, findings) for one phrase."""
    rates: List[float] = []
    findings: List[Finding] = []
    for guideline in guidelines or ():
        for rubric in guideline.rubrics:
            measured, finding = evaluate_rubric(ctx, guideline, rubric)
            if measured is not None:
                rates.append(measured)
            if finding is not None:
                findings.append(finding)
    score = round(100 * sum(rates) / len(rates)) if rates else None
    return score, findings
