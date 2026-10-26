"""Deterministic text -> rubric parsing from the keyword vocabulary.

"gaps between the notes is more then 0.5 sec"
    -> {"metric": "note_gap", "operator": "gt", "value": 0.5, "unit": "sec"}

It finds four things -- a metric phrase, a comparator, a number (two for
"between X and Y") and a unit -- and refuses to guess: if any is missing or
the unit doesn't fit the metric, `rule` is None and `missing` says what to
add. The author always confirms the structured rule before it is saved.
"""

import re
from typing import List, Optional, Tuple

from practice_hub.feedback_generator.guidelines import METRICS, unit_allowed

from . import vocab
from .base import ParseResult

NUMBER = r"(\d+(?:\.\d+)?|\.\d+)"


def _phrase_regex(phrases) -> re.Pattern:
    alternatives = sorted(phrases, key=len, reverse=True)
    parts = []
    for phrase in alternatives:
        escaped = re.escape(phrase).replace(r"\ ", r"\s+")
        if phrase[0].isalnum():
            escaped = r"\b" + escaped
        if phrase[-1].isalnum():
            escaped = escaped + r"\b"
        parts.append(escaped)
    return re.compile("|".join(parts))


_METRIC_RES = [(metric, _phrase_regex(phrases)) for metric, phrases in vocab.METRIC_PHRASES]
_COMPARATOR_RE = _phrase_regex(vocab.COMPARATORS)
_APPLIES_RES = [(name, _phrase_regex(phrases)) for name, phrases in vocab.APPLIES_TO_PHRASES]
_UNIT_RES = [(re.compile(r"\s*" + pattern), unit) for pattern, unit in vocab.UNIT_PATTERNS]
_NUMBER_RE = re.compile(NUMBER)
_BETWEEN_RE = re.compile(
    r"\bbetween\s+" + NUMBER + r"\s*(?P<unit1>[a-z%]+(?:\s+of\s+(?:a|the)\s+\w+)?)?\s*(?:and|to|-)\s*" + NUMBER
)
_WORD_RE = re.compile(r"[a-z]+")


def _normalise(text: str) -> str:
    lowered = text.lower()
    for pattern, replacement in vocab.TYPOS:
        lowered = re.sub(pattern, replacement, lowered)
    return lowered


def _unit_at(text: str, position: int) -> Optional[Tuple[str, int, int]]:
    """(unit, start, end) of a unit written right at `position`, if any."""
    for regex, unit in _UNIT_RES:
        match = regex.match(text, position)
        if match and match.end() > position:
            start = position + (len(match.group(0)) - len(match.group(0).lstrip()))
            return unit, start, match.end()
    return None


class KeywordTranslator:
    name = "keyword"

    def parse(self, text: str) -> ParseResult:
        source = (text or "")[:500]
        lowered = _normalise(source)
        spans: List[Tuple[int, int, str]] = []
        missing: List[str] = []

        metric = None
        for name, regex in _METRIC_RES:
            match = regex.search(lowered)
            if match:
                metric = name
                spans.append((match.start(), match.end(), "metric"))
                break
        if metric is None:
            missing.append("metric")

        operator = value = value_max = None
        unit = None
        between = _BETWEEN_RE.search(lowered)
        if between:
            operator = "between"
            value, value_max = float(between.group(1)), float(between.group(3))
            spans.append((between.start(), between.start() + len("between"), "comparator"))
            spans.append((between.start(1), between.end(1), "value"))
            spans.append((between.start(3), between.end(3), "value"))
            found = _unit_at(lowered, between.end(3))
            if found is None and between.group("unit1"):
                found = _unit_at(lowered, between.start("unit1"))
        else:
            comparator = _COMPARATOR_RE.search(lowered)
            if comparator:
                operator = vocab.COMPARATORS[re.sub(r"\s+", " ", comparator.group(0))]
                spans.append((comparator.start(), comparator.end(), "comparator"))
                number = _NUMBER_RE.search(lowered, comparator.end())
            else:
                missing.append("comparator")
                number = _NUMBER_RE.search(lowered)
            found = None
            if number:
                value = float(number.group(0))
                spans.append((number.start(), number.end(), "value"))
                found = _unit_at(lowered, number.end())
            else:
                missing.append("value")

        if found is not None:
            unit, start, end = found
            spans.append((start, end, "unit"))
        if unit == "pct":
            unit = vocab.BARE_PERCENT.get(metric)
        if unit is None and value is not None and metric is not None:
            unit = vocab.DEFAULT_UNIT.get(metric)
        if unit is None and value is not None:
            missing.append("unit")
        elif metric is not None and unit is not None and not unit_allowed(metric, unit):
            missing.append("unit")
            allowed = ", ".join(METRICS[metric].units)
            return self._result(
                source, None, spans, missing,
                f"{METRICS[metric].label} can't be measured in {unit}; use one of: {allowed}.",
            )

        applies_to = "all"
        for name, regex in _APPLIES_RES:
            match = regex.search(lowered)
            if match:
                applies_to = name
                spans.append((match.start(), match.end(), "applies_to"))
                break

        if missing:
            return self._result(source, None, spans, missing, _missing_message(missing))

        rule = {
            "metric": metric,
            "operator": operator,
            "value": value,
            "value_max": value_max,
            "unit": unit,
            "applies_to": applies_to,
        }
        return self._result(source, rule, spans, [], "")

    def _result(self, source, rule, spans, missing, message) -> ParseResult:
        lowered = _normalise(source)
        covered = [False] * len(lowered)
        for start, end, _ in spans:
            for i in range(start, min(end, len(covered))):
                covered[i] = True
        unrecognised = [
            m.group(0)
            for m in _WORD_RE.finditer(lowered)
            if not any(covered[m.start():m.end()]) and m.group(0) not in vocab.STOPWORDS
        ]
        return ParseResult(
            rule=rule,
            matched_spans=sorted(spans),
            unrecognised=unrecognised,
            missing=missing,
            message=message,
            translator=self.name,
        )


_HINTS = {
    "metric": "what to measure (e.g. \u201cgap between notes\u201d, \u201cheld\u201d, \u201ctiming\u201d, \u201cdynamic range\u201d)",
    "comparator": "a comparison (e.g. \u201cmore than\u201d, \u201cat least\u201d, \u201cunder\u201d, \u201cbetween \u2026 and \u2026\u201d)",
    "value": "a number",
    "unit": "a unit (e.g. \u201csec\u201d, \u201cms\u201d, \u201c% of the note\u201d, \u201c% of a beat\u201d)",
}


def _missing_message(missing) -> str:
    return "Couldn't find " + "; ".join(_HINTS[m] for m in missing) + "."
