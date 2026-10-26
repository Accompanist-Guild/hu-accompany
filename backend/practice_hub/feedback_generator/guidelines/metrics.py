"""What a rubric can measure.

Each metric turns one phrase's aligned notes (a PhraseContext) into
Measurements: a value in the metric's native unit, the bar it happened in,
and the written note it belongs to (relative units like "% of the note" are
resolved against that note). Metrics only measure; whether a value is good
is the rubric's call (evaluator.py).

Add a metric by writing a measure function and registering a Metric in
METRICS. Its `units` are what an author may write the threshold in.
"""

from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Tuple

from ..judges import ExpectedNote, PhraseContext, UserNote
from ..judges.phase1.articulation import marking_of

# Written notes closer together than this count as touching (no written
# rest between them), so the played gap is articulation, not a rest.
TOUCHING_WRITTEN_GAP_MS = 20.0


@dataclass(frozen=True)
class Measurement:
    value: float  # in the metric's native unit
    bar: int
    expected: Optional[ExpectedNote]  # None for phrase-level measurements


@dataclass(frozen=True)
class Metric:
    name: str
    label: str
    description: str
    native_unit: str  # "ms" | "ratio" | "volume"
    units: Tuple[str, ...]
    # What one measurement is, for messages ("note gaps", "notes").
    noun: str
    measure: Callable[[PhraseContext, str], List[Measurement]]


# --- applies_to filtering -----------------------------------------------------


def applies(expected: ExpectedNote, applies_to: str) -> bool:
    if applies_to == "all":
        return True
    marking = marking_of(expected)
    if applies_to == "unmarked":
        return marking is None
    return marking == applies_to


def _matched_by_expected(ctx: PhraseContext) -> Dict[int, UserNote]:
    return {id(expected): user for expected, user in ctx.matched}


def _written_order(ctx: PhraseContext) -> List[ExpectedNote]:
    notes = [expected for expected, _ in ctx.matched] + list(ctx.missing)
    return sorted(notes, key=lambda n: (n.start_time_ms, n.note_id))


# --- Measures -----------------------------------------------------------------


def _note_gap(ctx: PhraseContext, applies_to: str) -> List[Measurement]:
    """Silence the player left between two consecutive written notes:
    next played onset minus this played offset (negative = overlap).

    Only pairs that are adjacent in the score and both played are measured,
    so a dropped note doesn't turn into one huge "gap". Pairs with a written
    rest between them, or sharing an onset (a chord), are skipped -- the gap
    there is the composer's, not the player's touch."""
    played = _matched_by_expected(ctx)
    written = _written_order(ctx)
    out: List[Measurement] = []
    for current, following in zip(written, written[1:]):
        if following.start_time_ms <= current.start_time_ms:
            continue
        if following.start_time_ms - current.end_time_ms > TOUCHING_WRITTEN_GAP_MS:
            continue
        current_user = played.get(id(current))
        following_user = played.get(id(following))
        if current_user is None or following_user is None:
            continue
        if not applies(current, applies_to):
            continue
        gap = following_user.start_time_ms - current_user.end_time_ms
        out.append(Measurement(value=gap, bar=ctx.bar(current.start_time_ms), expected=current))
    return out


def _sounding_ratio(ctx: PhraseContext, applies_to: str) -> List[Measurement]:
    """How long each note sounded relative to its written length (1.0 = full
    value, 0.5 = half)."""
    out: List[Measurement] = []
    for expected, user in ctx.matched:
        if expected.duration_ms <= 0 or not applies(expected, applies_to):
            continue
        out.append(
            Measurement(
                value=user.duration_ms / expected.duration_ms,
                bar=ctx.bar(expected.start_time_ms),
                expected=expected,
            )
        )
    return out


def _onset_deviation(ctx: PhraseContext, applies_to: str) -> List[Measurement]:
    """How far each played onset was from the written one, early or late."""
    return [
        Measurement(
            value=abs(user.start_time_ms - expected.start_time_ms),
            bar=ctx.bar(expected.start_time_ms),
            expected=expected,
        )
        for expected, user in ctx.matched
        if applies(expected, applies_to)
    ]


def _volume_range(ctx: PhraseContext, applies_to: str) -> List[Measurement]:
    """Loudest minus softest played note in the phrase, on native_ffi's 0-1
    volume scale (0.1 = 6 dB). One measurement per phrase; none when fewer
    than two notes carry a volume."""
    notes = [
        (expected, user)
        for expected, user in ctx.matched
        if user.volume is not None and applies(expected, applies_to)
    ]
    if len(notes) < 2:
        return []
    volumes = [user.volume for _, user in notes]
    first = min(notes, key=lambda pair: pair[0].start_time_ms)[0]
    return [Measurement(value=max(volumes) - min(volumes), bar=ctx.bar(first.start_time_ms), expected=None)]


METRICS: Dict[str, Metric] = {
    metric.name: metric
    for metric in (
        Metric(
            name="note_gap",
            label="Gap between notes",
            description="Silence between one played note's release and the next note's attack.",
            native_unit="ms",
            units=("ms", "sec", "pct_of_note", "pct_of_beat"),
            noun="note gaps",
            measure=_note_gap,
        ),
        Metric(
            name="sounding_ratio",
            label="Sounding length",
            description="How long each note sounded compared to its written length.",
            native_unit="ratio",
            units=("pct_of_note", "ratio"),
            noun="notes",
            measure=_sounding_ratio,
        ),
        Metric(
            name="onset_deviation",
            label="Timing deviation",
            description="How far each note's attack was from where it is written, early or late.",
            native_unit="ms",
            units=("ms", "sec", "pct_of_beat"),
            noun="notes",
            measure=_onset_deviation,
        ),
        Metric(
            name="volume_range",
            label="Dynamic range",
            description="Difference between the loudest and softest note in the phrase.",
            native_unit="volume",
            units=("volume", "db"),
            noun="phrases",
            measure=_volume_range,
        ),
    )
}

UNITS = {
    "ms": "ms",
    "sec": "sec",
    "pct_of_note": "% of the note",
    "pct_of_beat": "% of a beat",
    "ratio": "× written length",
    "volume": "volume (0–1)",
    "db": "dB",
}


def to_native(value: float, unit: str, metric: Metric, measurement: Measurement, beat_ms: float) -> float:
    """An author's threshold, converted into the metric's native unit for
    this one measurement."""
    if metric.native_unit == "ms":
        if unit == "ms":
            return value
        if unit == "sec":
            return value * 1000.0
        if unit == "pct_of_beat":
            return value / 100.0 * beat_ms
        if unit == "pct_of_note":
            written = measurement.expected.duration_ms if measurement.expected else beat_ms
            return value / 100.0 * written
    if metric.native_unit == "ratio":
        if unit == "ratio":
            return value
        if unit == "pct_of_note":
            return value / 100.0
    if metric.native_unit == "volume":
        if unit == "volume":
            return value
        if unit == "db":
            return value / 60.0  # native_ffi volume: 1.0 spans 60 dB
    raise ValueError(f"unit {unit!r} is not valid for metric {metric.name!r}")


def unit_allowed(metric_name: str, unit: str) -> bool:
    metric = METRICS.get(metric_name)
    return metric is not None and unit in metric.units
