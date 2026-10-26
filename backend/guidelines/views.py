"""Guidelines over HTTP (see guidelines/urls.py).

Reading is open: anyone gets published, public guidelines. Writing needs a
bearer token of an admin or verified contributor (permissions.py);
contributors may only change guidelines they own.

GET    /api/guidelines                       ?tags=a,b  ?mine=1  ?all=1 -> {guidelines}
POST   /api/guidelines                       author  -> 201 {guideline}
GET    /api/guidelines/<id>                  -> {guideline}
PUT    /api/guidelines/<id>                  owner/admin -> {guideline} (version + 1)
DELETE /api/guidelines/<id>                  owner/admin -> 204
GET    /api/guidelines/for-score/<score_id>  -> {score_id, tags, guidelines}
GET    /api/guidelines/tags                  -> {tags: [{slug, kind}]}
GET    /api/guidelines/vocabulary            -> metrics/units/operators for the editor
POST   /api/guidelines/rubrics/parse         author  {text} -> ParseResult
PATCH  /api/scores/<id>/tags                 author  {tags, composed_date?} -> {score}

Errors are {error, code} like User_accounts, plus `fields` on validation.
"""

import json

from django.core.exceptions import ValidationError
from django.db import transaction
from django.http import HttpResponse, JsonResponse
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods

from practice_hub.feedback_generator.guidelines import APPLIES_TO, METRICS, OPERATORS, SEVERITIES, UNITS
from User_accounts.models import AuthToken
from User_accounts.tokens import _hash, presented

from . import services
from .models import (
    MAX_BODY,
    MAX_SOURCE_TEXT,
    MAX_TITLE,
    Guideline,
    Rubric,
    Tag,
    slugify_tag,
    validate_slug,
)
from .parsing import get_translator
from .permissions import author_required, can_author, can_edit, is_admin

MAX_TAGS = 20
MAX_RUBRICS = 20
RUBRIC_FIELDS = (
    "label", "source_text", "metric", "operator", "value", "value_max", "unit", "applies_to",
    "pass_rate", "severity", "fail_message", "suggestion", "enabled",
)


# --- Helpers ------------------------------------------------------------------


def error(message, status, code, **extra):
    return JsonResponse({"error": message, "code": code, **extra}, status=status)


def read_json(request):
    try:
        data = json.loads(request.body or b"{}")
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None
    return data if isinstance(data, dict) else None


def optional_user(request):
    """The signed-in user if a valid bearer token came with the request, else None."""
    token = presented(request)
    if not token:
        return None
    row = AuthToken.objects.select_related("user").filter(key_hash=_hash(token)).first()
    return row.user if row is not None and row.user.is_active else None


def rubric_json(rubric: Rubric) -> dict:
    return {"id": rubric.pk, **{name: getattr(rubric, name) for name in RUBRIC_FIELDS}}


def guideline_json(guideline: Guideline, user=None) -> dict:
    return {
        "id": guideline.pk,
        "title": guideline.title,
        "body": guideline.body,
        "tags": [tag.slug for tag in guideline.tags.all()],
        "status": guideline.status,
        "visibility": guideline.visibility,
        "version": guideline.version,
        "owner_name": guideline.owner.first_name if guideline.owner else "",
        "editable": bool(user) and can_edit(user, guideline),
        "created_at": guideline.created_at.isoformat(),
        "updated_at": guideline.updated_at.isoformat(),
        "rubrics": [rubric_json(rubric) for rubric in guideline.rubrics.all()],
    }


def _with_relations(queryset):
    return queryset.select_related("owner").prefetch_related("tags", "rubrics")


def _visible_to(user, guideline) -> bool:
    published = guideline.status == Guideline.PUBLISHED and guideline.visibility == Guideline.PUBLIC
    return published or (user is not None and can_edit(user, guideline))


def _tag_list(raw):
    """Validated, de-duplicated slugs, or raises ValidationError."""
    if raw is None:
        return []
    if not isinstance(raw, list) or len(raw) > MAX_TAGS:
        raise ValidationError(f"tags must be a list of at most {MAX_TAGS} tags.")
    slugs = []
    for item in raw:
        if not isinstance(item, str):
            raise ValidationError("Every tag must be text.")
        slug = slugify_tag(item)
        validate_slug(slug)
        slugs.append(slug)
    return list(dict.fromkeys(slugs))


def _tag_rows(slugs):
    return [
        tag
        for slug in slugs
        for tag in services.tag_objects([slug], Tag.ERA if slug in services.ERA_SLUGS else Tag.OTHER)
    ]


def _build_rubrics(raw):
    """(unsaved Rubric list, field errors) from the request's rubric list."""
    if raw is None:
        return [], {}
    if not isinstance(raw, list) or len(raw) > MAX_RUBRICS:
        return [], {"rubrics": f"rubrics must be a list of at most {MAX_RUBRICS}."}
    rubrics, errors = [], {}
    for index, item in enumerate(raw):
        if not isinstance(item, dict):
            errors[f"rubrics[{index}]"] = "Each rubric must be an object."
            continue
        values = {name: item[name] for name in RUBRIC_FIELDS if name in item}
        for name in ("value", "value_max", "pass_rate"):
            if name in values and values[name] is not None and (
                not isinstance(values[name], (int, float)) or isinstance(values[name], bool)
            ):
                errors[f"rubrics[{index}].{name}"] = f"{name} must be a number."
        for name in ("label", "source_text", "fail_message", "suggestion", "metric", "operator", "unit",
                     "applies_to", "severity"):
            if name in values and not isinstance(values[name], str):
                errors[f"rubrics[{index}].{name}"] = f"{name} must be text."
        if "enabled" in values and not isinstance(values["enabled"], bool):
            errors[f"rubrics[{index}].enabled"] = "enabled must be true or false."
        if f"rubrics[{index}]" in errors or any(k.startswith(f"rubrics[{index}].") for k in errors):
            continue
        rubric = Rubric(**values, position=index)
        rubric_id = item.get("id")
        if isinstance(rubric_id, int) and not isinstance(rubric_id, bool):
            rubric.pk = rubric_id
        try:
            rubric.full_clean(exclude=["guideline"], validate_unique=False)
        except ValidationError as e:
            for name, messages in e.message_dict.items():
                errors[f"rubrics[{index}].{name}"] = " ".join(messages)
            continue
        rubrics.append(rubric)
    return rubrics, errors


def _apply(guideline: Guideline, data: dict, partial_ok: bool):
    """Validate `data` onto `guideline`; returns (tag slugs, rubrics, errors)."""
    errors = {}
    if "title" in data or not partial_ok:
        title = data.get("title")
        if not isinstance(title, str) or not title.strip() or len(title.strip()) > MAX_TITLE:
            errors["title"] = f"A title of 1-{MAX_TITLE} characters is required."
        else:
            guideline.title = title.strip()
    if "body" in data:
        body = data.get("body")
        if not isinstance(body, str) or len(body) > MAX_BODY:
            errors["body"] = f"body must be text of at most {MAX_BODY} characters."
        else:
            guideline.body = body
    if "status" in data:
        if data["status"] not in (Guideline.DRAFT, Guideline.PUBLISHED):
            errors["status"] = "status must be draft or published."
        else:
            guideline.status = data["status"]
    if "visibility" in data and data["visibility"] != Guideline.PUBLIC:
        errors["visibility"] = "Only public guidelines are supported for now."

    slugs = None
    if "tags" in data or not partial_ok:
        try:
            slugs = _tag_list(data.get("tags"))
        except ValidationError as e:
            errors["tags"] = " ".join(e.messages)

    rubrics = None
    if "rubrics" in data or not partial_ok:
        rubrics, rubric_errors = _build_rubrics(data.get("rubrics"))
        errors.update(rubric_errors)
    for rubric in rubrics or []:
        if len(rubric.source_text) > MAX_SOURCE_TEXT:
            errors["source_text"] = f"source_text is limited to {MAX_SOURCE_TEXT} characters."
    return slugs, rubrics, errors


@transaction.atomic
def _save(guideline: Guideline, slugs, rubrics):
    guideline.save()
    if slugs is not None:
        guideline.tags.set(_tag_rows(slugs))
    if rubrics is not None:
        existing = {r.pk: r for r in guideline.rubrics.all()}
        keep = set()
        for rubric in rubrics:
            if rubric.pk in existing:
                keep.add(rubric.pk)
            else:
                rubric.pk = None
            rubric.guideline = guideline
            rubric.save()
        guideline.rubrics.exclude(pk__in=keep | {r.pk for r in rubrics}).delete()


# --- Views --------------------------------------------------------------------


@csrf_exempt
@require_http_methods(["GET", "POST"])
def guidelines_view(request):
    if request.method == "POST":
        return _create(request)

    user = optional_user(request)
    queryset = Guideline.objects.all()
    if request.GET.get("mine") == "1" and user is not None and can_author(user):
        queryset = queryset.filter(owner=user)
    elif request.GET.get("all") == "1" and user is not None and is_admin(user):
        pass
    elif request.GET.get("all") == "1" and user is not None and can_author(user):
        queryset = services.published(queryset) | queryset.filter(owner=user)
    else:
        queryset = services.published(queryset)

    tags = [t for t in (request.GET.get("tags") or "").split(",") if t.strip()]
    if tags:
        queryset = queryset.filter(tags__slug__in=[slugify_tag(t) for t in tags[:MAX_TAGS]])
    queryset = _with_relations(queryset.distinct())
    return JsonResponse({"guidelines": [guideline_json(g, user) for g in queryset]})


@author_required
def _create(request):
    data = read_json(request)
    if data is None:
        return error("Send the guideline as JSON.", 400, "bad_request")
    guideline = Guideline(owner=request.user, visibility=Guideline.PUBLIC)
    slugs, rubrics, errors = _apply(guideline, data, partial_ok=False)
    if errors:
        return error("Some fields need fixing.", 400, "invalid", fields=errors)
    _save(guideline, slugs, rubrics)
    guideline = _with_relations(Guideline.objects.filter(pk=guideline.pk)).get()
    return JsonResponse({"guideline": guideline_json(guideline, request.user)}, status=201)


@csrf_exempt
@require_http_methods(["GET", "PUT", "DELETE"])
def guideline_view(request, guideline_id: int):
    if request.method == "GET":
        user = optional_user(request)
        guideline = _with_relations(Guideline.objects.filter(pk=guideline_id)).first()
        if guideline is None or not _visible_to(user, guideline):
            return error("That guideline doesn't exist.", 404, "not_found")
        return JsonResponse({"guideline": guideline_json(guideline, user)})
    return _change(request, guideline_id)


@author_required
def _change(request, guideline_id: int):
    guideline = Guideline.objects.filter(pk=guideline_id).first()
    if guideline is None:
        return error("That guideline doesn't exist.", 404, "not_found")
    if not can_edit(request.user, guideline):
        return error("You can only change guidelines you wrote.", 403, "forbidden")
    if request.method == "DELETE":
        guideline.delete()
        return HttpResponse(status=204)

    data = read_json(request)
    if data is None:
        return error("Send the guideline as JSON.", 400, "bad_request")
    slugs, rubrics, errors = _apply(guideline, data, partial_ok=True)
    if errors:
        return error("Some fields need fixing.", 400, "invalid", fields=errors)
    guideline.version += 1
    _save(guideline, slugs, rubrics)
    guideline = _with_relations(Guideline.objects.filter(pk=guideline.pk)).get()
    return JsonResponse({"guideline": guideline_json(guideline, request.user)})


@require_GET
def for_score_view(request, score_id: int):
    tags = services.tags_for_score(score_id)
    guidelines = _with_relations(services.matching(tags)) if tags else []
    return JsonResponse(
        {"score_id": score_id, "tags": tags, "guidelines": [guideline_json(g) for g in guidelines]}
    )


@require_GET
def tags_view(request):
    return JsonResponse({"tags": [{"slug": t.slug, "kind": t.kind} for t in Tag.objects.all()]})


@require_GET
def vocabulary_view(request):
    """What the editor's dropdowns offer, straight from the engine's registry."""
    return JsonResponse(
        {
            "metrics": [
                {"name": m.name, "label": m.label, "description": m.description, "units": list(m.units)}
                for m in METRICS.values()
            ],
            "units": [{"name": name, "label": label} for name, label in UNITS.items()],
            "operators": list(OPERATORS),
            "applies_to": list(APPLIES_TO),
            "severities": list(SEVERITIES),
        }
    )


@csrf_exempt
@require_http_methods(["POST"])
@author_required
def parse_rubric_view(request):
    data = read_json(request)
    text = data.get("text") if data else None
    if not isinstance(text, str) or not text.strip():
        return error("Send the rubric as {\"text\": \"...\"}.", 400, "bad_request")
    if len(text) > MAX_SOURCE_TEXT:
        return error(f"Keep rubric text under {MAX_SOURCE_TEXT} characters.", 400, "too_long")
    return JsonResponse(get_translator().parse(text).as_json())


@csrf_exempt
@require_http_methods(["PATCH"])
@author_required
def score_tags_view(request, score_id: int):
    from scores.models import Score

    score = Score.objects.filter(pk=score_id).first()
    if score is None:
        return error("That score doesn't exist.", 404, "not_found")
    data = read_json(request)
    if data is None:
        return error("Send {\"tags\": [...]} as JSON.", 400, "bad_request")
    try:
        slugs = _tag_list(data.get("tags")) if "tags" in data else None
    except ValidationError as e:
        return error(" ".join(e.messages), 400, "invalid")
    composed_date = data.get("composed_date")
    if composed_date is not None and (not isinstance(composed_date, str) or len(composed_date) > 100):
        return error("composed_date must be text of at most 100 characters.", 400, "invalid")

    with transaction.atomic():
        if slugs is not None:
            # Era tags follow composed_date, so a hand-typed era tag is
            # dropped again by the save below unless the date agrees.
            score.tags.set(_tag_rows(slugs))
        if composed_date is not None:
            score.composed_date = composed_date.strip()
        score.save()
    score = Score.objects.prefetch_related("tags").get(pk=score.pk)
    return JsonResponse({"score": score.as_summary()})
