"""Authored guidelines (how to play / what to listen for) and their rubrics.

A Guideline is tutorial text attached to tags ("baroque", "bach", "fugue").
It applies to every piece sharing ANY of its tags. Its Rubrics are the
measurable half -- each one is converted to a framework-free RubricSpec
(practice_hub.feedback_generator.guidelines) and checked on every phrase.

`owner` and `visibility` are here so per-user and shared guidelines can be
added later; today only admins / verified contributors author, and only
`public` + `published` guidelines are ever shown to players.
"""

import re

from django.conf import settings
from django.core.exceptions import ValidationError
from django.db import models

from practice_hub.feedback_generator.guidelines import (
    APPLIES_TO,
    DEFAULT_PASS_RATE,
    METRICS,
    OPERATORS,
    SEVERITIES,
    GuidelineSpec,
    RubricSpec,
    unit_allowed,
)

SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
MAX_SLUG = 60
MAX_TITLE = 200
MAX_BODY = 20_000
MAX_SOURCE_TEXT = 500
MAX_MESSAGE = 500


def slugify_tag(text: str) -> str:
    """"J.S. Bach" -> "j-s-bach"; "" when nothing usable is left."""
    slug = re.sub(r"[^a-z0-9]+", "-", str(text or "").lower()).strip("-")
    return slug[:MAX_SLUG].strip("-")


def validate_slug(value: str) -> None:
    if not isinstance(value, str) or not value or len(value) > MAX_SLUG or not SLUG_RE.match(value):
        raise ValidationError(f"{value!r} is not a valid tag (lowercase letters, digits and dashes).")


class Tag(models.Model):
    ERA = "era"
    COMPOSER = "composer"
    FORM = "form"
    TECHNIQUE = "technique"
    OTHER = "other"
    KINDS = [(k, k) for k in (ERA, COMPOSER, FORM, TECHNIQUE, OTHER)]

    slug = models.CharField(max_length=MAX_SLUG, unique=True, validators=[validate_slug])
    kind = models.CharField(max_length=20, choices=KINDS, default=OTHER)

    class Meta:
        ordering = ["slug"]

    def __str__(self):
        return self.slug


class Guideline(models.Model):
    DRAFT = "draft"
    PUBLISHED = "published"
    STATUSES = [(DRAFT, "draft"), (PUBLISHED, "published")]

    PUBLIC = "public"
    PRIVATE = "private"
    SHARED = "shared"
    VISIBILITIES = [(PUBLIC, "public"), (PRIVATE, "private"), (SHARED, "shared")]

    title = models.CharField(max_length=MAX_TITLE)
    body = models.TextField(blank=True, max_length=MAX_BODY)
    tags = models.ManyToManyField(Tag, related_name="guidelines", blank=True)
    status = models.CharField(max_length=20, choices=STATUSES, default=DRAFT)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.SET_NULL, related_name="guidelines"
    )
    visibility = models.CharField(max_length=20, choices=VISIBILITIES, default=PUBLIC)
    # Bumped on every edit, and recorded in each phrase file a guideline
    # judged, so stored feedback says which wording/rules produced it.
    version = models.PositiveIntegerField(default=1)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["title", "id"]

    def __str__(self):
        return self.title

    def to_spec(self) -> GuidelineSpec:
        return GuidelineSpec(
            id=self.pk,
            title=self.title,
            version=self.version,
            body=self.body,
            tags=tuple(tag.slug for tag in self.tags.all()),
            rubrics=tuple(rubric.to_spec() for rubric in self.rubrics.all() if rubric.enabled),
        )


class Rubric(models.Model):
    OPERATOR_CHOICES = [(o, o) for o in OPERATORS]
    APPLIES_CHOICES = [(a, a) for a in APPLIES_TO]
    SEVERITY_CHOICES = [(s, s) for s in SEVERITIES]
    METRIC_CHOICES = [(name, metric.label) for name, metric in METRICS.items()]
    UNIT_CHOICES = sorted({(unit, unit) for metric in METRICS.values() for unit in metric.units})

    guideline = models.ForeignKey(Guideline, on_delete=models.CASCADE, related_name="rubrics")
    label = models.CharField(max_length=MAX_TITLE, blank=True)
    # What the author typed, kept so the editor can show it next to the
    # structured rule the parser made of it.
    source_text = models.CharField(max_length=MAX_SOURCE_TEXT, blank=True)
    metric = models.CharField(max_length=40, choices=METRIC_CHOICES)
    operator = models.CharField(max_length=10, choices=OPERATOR_CHOICES)
    value = models.FloatField()
    value_max = models.FloatField(null=True, blank=True)
    unit = models.CharField(max_length=20, choices=UNIT_CHOICES)
    applies_to = models.CharField(max_length=20, choices=APPLIES_CHOICES, default="all")
    pass_rate = models.FloatField(default=DEFAULT_PASS_RATE)
    severity = models.CharField(max_length=10, choices=SEVERITY_CHOICES, default="minor")
    fail_message = models.CharField(max_length=MAX_MESSAGE, blank=True)
    suggestion = models.CharField(max_length=MAX_MESSAGE, blank=True)
    enabled = models.BooleanField(default=True)
    position = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["position", "id"]

    def __str__(self):
        return self.label or f"{self.metric} {self.operator} {self.value} {self.unit}"

    def clean(self):
        errors = {}
        if self.metric not in METRICS:
            errors["metric"] = f"Unknown metric {self.metric!r}."
        elif not unit_allowed(self.metric, self.unit):
            allowed = ", ".join(METRICS[self.metric].units)
            errors["unit"] = f"{self.metric} can be measured in: {allowed}."
        if self.operator not in OPERATORS:
            errors["operator"] = f"Unknown operator {self.operator!r}."
        elif self.operator == "between" and self.value_max is None:
            errors["value_max"] = "A 'between' rule needs an upper value."
        if self.pass_rate is None or not 0 < self.pass_rate <= 1:
            errors["pass_rate"] = "Pass rate must be above 0 and at most 1."
        if self.applies_to not in APPLIES_TO:
            errors["applies_to"] = f"Unknown note filter {self.applies_to!r}."
        if self.severity not in SEVERITIES:
            errors["severity"] = f"Unknown severity {self.severity!r}."
        if errors:
            raise ValidationError(errors)

    def to_spec(self) -> RubricSpec:
        return RubricSpec(
            id=self.pk,
            metric=self.metric,
            operator=self.operator,
            value=self.value,
            value_max=self.value_max,
            unit=self.unit,
            label=self.label,
            applies_to=self.applies_to,
            pass_rate=self.pass_rate,
            severity=self.severity,
            fail_message=self.fail_message,
            suggestion=self.suggestion,
        )
