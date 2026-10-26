"""Authored guidelines and rubrics, checked on top of the built-in judges.

Guidelines are written by admins / verified contributors (the `guidelines`
Django app stores them) and attached to tags such as "baroque" or "bach".
This package is the framework-free half: the shapes the engine evaluates
(types.py), what a rubric can measure (metrics.py), and the check itself
(evaluator.py).
"""

from .evaluator import CATEGORY, evaluate_guidelines, evaluate_rubric
from .metrics import METRICS, UNITS, unit_allowed
from .types import APPLIES_TO, DEFAULT_PASS_RATE, OPERATORS, SEVERITIES, GuidelineSpec, RubricSpec

__all__ = [
    "CATEGORY",
    "evaluate_guidelines",
    "evaluate_rubric",
    "METRICS",
    "UNITS",
    "unit_allowed",
    "APPLIES_TO",
    "DEFAULT_PASS_RATE",
    "OPERATORS",
    "SEVERITIES",
    "GuidelineSpec",
    "RubricSpec",
]
