"""Framework-free shapes the guideline layer evaluates.

The `guidelines` Django app stores authored guidelines and converts them to
these (Guideline.to_spec / Rubric.to_spec), so the engine never imports the
ORM -- the same split the rest of feedback_generator keeps.
"""

from dataclasses import dataclass, field
from typing import Optional, Tuple

OPERATORS = ("gt", "gte", "lt", "lte", "between")
APPLIES_TO = ("all", "staccato", "legato", "unmarked")
SEVERITIES = ("minor", "major")
DEFAULT_PASS_RATE = 0.8


@dataclass(frozen=True)
class RubricSpec:
    """One measurable rule: `metric <operator> value [unit]`, checked on every
    note (or note pair) it applies to. The rubric passes when at least
    `pass_rate` of those measurements meet the rule.

    `value`/`value_max` are in `unit` as the author wrote them (0.5 sec stays
    0.5 / "sec"); the evaluator converts per measurement, because relative
    units (% of the note, % of a beat) depend on each note and the tempo.
    """

    metric: str
    operator: str
    value: float
    unit: str
    value_max: Optional[float] = None
    id: Optional[int] = None
    label: str = ""
    applies_to: str = "all"
    pass_rate: float = DEFAULT_PASS_RATE
    severity: str = "minor"
    fail_message: str = ""
    suggestion: str = ""


@dataclass(frozen=True)
class GuidelineSpec:
    """An authored guideline as the engine sees it: who it is (for the
    findings it produces) plus its enabled rubrics. A guideline with no
    rubrics is tutorial text only and produces no findings."""

    id: Optional[int]
    title: str
    version: int = 1
    rubrics: Tuple[RubricSpec, ...] = field(default_factory=tuple)
    body: str = ""
    tags: Tuple[str, ...] = field(default_factory=tuple)
