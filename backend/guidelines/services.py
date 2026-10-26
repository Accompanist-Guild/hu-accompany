"""Tag bookkeeping and guideline lookup shared by the API and the feedback view."""

from typing import Iterable, List

from django.db import transaction

from practice_hub.feedback_generator.guidelines import GuidelineSpec
from practice_hub.feedback_generator.judges.phase2.era import (
    ERA_PROFILES,
    era_for_year,
    parse_composed_year,
)

from .models import Guideline, Tag, slugify_tag

ERA_SLUGS = frozenset(slugify_tag(profile.era) for profile in ERA_PROFILES)


def era_slug_for(composed_date) -> str:
    """"ca. 1720" -> "baroque"; "" when the date says nothing."""
    profile = era_for_year(parse_composed_year(composed_date))
    return slugify_tag(profile.era) if profile else ""


def tag_objects(slugs: Iterable[str], kind: str = Tag.OTHER) -> List[Tag]:
    """Tag rows for `slugs`, creating any that don't exist yet with `kind`."""
    out = []
    for slug in dict.fromkeys(s for s in slugs if s):
        tag, _ = Tag.objects.get_or_create(slug=slug, defaults={"kind": kind})
        out.append(tag)
    return out


@transaction.atomic
def sync_auto_tags(score) -> None:
    """Keep a score's derived tags in step with its data: exactly one era
    tag (from composed_date, none when the date is unknown) and a composer
    tag. Every other tag on the score -- the manual ones -- is left alone."""
    wanted_era = era_slug_for(score.composed_date)
    stale = [tag for tag in score.tags.all() if tag.slug in ERA_SLUGS and tag.slug != wanted_era]
    if stale:
        score.tags.remove(*stale)
    if wanted_era:
        score.tags.add(*tag_objects([wanted_era], Tag.ERA))
    composer = slugify_tag(score.composer)
    if composer and composer not in ("anon", "anonymous", "unknown", "traditional"):
        score.tags.add(*tag_objects([composer], Tag.COMPOSER))


def published(queryset=None):
    """What players may see: published and public."""
    queryset = Guideline.objects.all() if queryset is None else queryset
    return queryset.filter(status=Guideline.PUBLISHED, visibility=Guideline.PUBLIC)


def matching(tags: Iterable[str], queryset=None):
    """Published public guidelines sharing ANY of `tags`."""
    slugs = [slugify_tag(t) for t in tags or () if isinstance(t, str)]
    slugs = [s for s in slugs if s]
    if not slugs:
        return Guideline.objects.none()
    return (
        published(queryset)
        .filter(tags__slug__in=slugs)
        .distinct()
        .prefetch_related("tags", "rubrics")
    )


def resolve_guidelines(tags: Iterable[str]) -> List[GuidelineSpec]:
    return [guideline.to_spec() for guideline in matching(tags)]


def tags_for_score(score_id) -> List[str]:
    from scores.models import Score

    score = Score.objects.filter(pk=score_id).prefetch_related("tags").first()
    return [tag.slug for tag in score.tags.all()] if score else []
