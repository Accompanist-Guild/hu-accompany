from django.contrib.auth import get_user_model
from django.contrib.auth.models import Group
from django.core.exceptions import ValidationError
from django.test import TestCase

from scores.models import Score

from . import services
from .models import Guideline, Rubric, Tag, slugify_tag
from .permissions import CONTRIBUTOR_GROUP, can_author, can_edit, roles_of

User = get_user_model()


def make_user(email, staff=False, contributor=False):
    user = User.objects.create_user(username=email, email=email, password="correct horse", is_staff=staff)
    if contributor:
        user.groups.add(Group.objects.get(name=CONTRIBUTOR_GROUP))
    return user


def make_score(n=1, **kwargs):
    defaults = dict(
        title=f"Piece {n}", composer="J. S. Bach", pdmx_path=f"mxl/{n}.mxl", musicxml_path=f"musicxml/{n}.musicxml",
        sha256=str(n) * 8, part_count=1, measure_count=4,
    )
    defaults.update(kwargs)
    return Score.objects.create(**defaults)


def make_guideline(title="Baroque: detached touch", tags=("baroque",), status=Guideline.PUBLISHED, owner=None, **kw):
    guideline = Guideline.objects.create(title=title, body="Play detached.", status=status, owner=owner, **kw)
    guideline.tags.set(services.tag_objects(tags))
    return guideline


def gap_rubric(guideline, **kwargs):
    defaults = dict(metric="note_gap", operator="gt", value=0.5, unit="sec")
    defaults.update(kwargs)
    return Rubric.objects.create(guideline=guideline, **defaults)


class RubricValidationTests(TestCase):
    def rubric(self, **kwargs):
        return Rubric(guideline=make_guideline(), **{**dict(metric="note_gap", operator="gt", value=1, unit="ms"), **kwargs})

    def test_valid_rubric(self):
        self.rubric().full_clean()

    def test_rejections(self):
        cases = {
            "metric": dict(metric="nope"),
            "unit": dict(unit="volume"),
            "value_max": dict(operator="between"),
            "pass_rate": dict(pass_rate=0),
        }
        for field, kwargs in cases.items():
            with self.subTest(field=field), self.assertRaises(ValidationError) as caught:
                self.rubric(**kwargs).full_clean()
            self.assertIn(field, caught.exception.message_dict)

    def test_to_spec_skips_disabled_rubrics(self):
        guideline = make_guideline()
        on = gap_rubric(guideline, label="Detached")
        gap_rubric(guideline, enabled=False)
        spec = guideline.to_spec()
        self.assertEqual(spec.title, "Baroque: detached touch")
        self.assertEqual(spec.tags, ("baroque",))
        self.assertEqual([r.id for r in spec.rubrics], [on.pk])
        self.assertEqual(spec.rubrics[0].unit, "sec")

    def test_slugify(self):
        self.assertEqual(slugify_tag("J. S. Bach"), "j-s-bach")
        self.assertEqual(slugify_tag("  "), "")


class PermissionTests(TestCase):
    def test_roles(self):
        admin = make_user("a@x.co", staff=True)
        contributor = make_user("c@x.co", contributor=True)
        player = make_user("p@x.co")
        self.assertEqual((can_author(admin), can_author(contributor), can_author(player)), (True, True, False))
        self.assertEqual(roles_of(admin), ["admin"])
        self.assertEqual(roles_of(contributor), ["contributor"])
        self.assertEqual(roles_of(player), [])

    def test_contributors_edit_only_their_own(self):
        admin = make_user("a@x.co", staff=True)
        mine = make_user("c@x.co", contributor=True)
        other = make_user("d@x.co", contributor=True)
        guideline = make_guideline(owner=mine)
        self.assertTrue(can_edit(mine, guideline))
        self.assertFalse(can_edit(other, guideline))
        self.assertTrue(can_edit(admin, guideline))


class ScoreTagTests(TestCase):
    def slugs(self, score):
        return sorted(t.slug for t in Score.objects.get(pk=score.pk).tags.all())

    def test_era_and_composer_tags_derived(self):
        score = make_score(composed_date="ca. 1720")
        self.assertEqual(self.slugs(score), ["baroque", "j-s-bach"])
        self.assertEqual(Tag.objects.get(slug="baroque").kind, Tag.ERA)

    def test_date_change_swaps_era_and_keeps_manual_tags(self):
        score = make_score(composed_date="1722")
        score.tags.add(*services.tag_objects(["fugue"]))
        score.composed_date = "1830s"
        score.save()
        self.assertEqual(self.slugs(score), ["fugue", "j-s-bach", "romantic"])
        score.composed_date = ""
        score.save()
        self.assertEqual(self.slugs(score), ["fugue", "j-s-bach"])

    def test_summary_includes_tags(self):
        summary = make_score(composed_date="1722").as_summary()
        self.assertEqual(summary["composed_date"], "1722")
        self.assertIn("baroque", summary["tags"])

    def test_resolve_matches_any_tag_and_skips_drafts(self):
        published = make_guideline()
        gap_rubric(published)
        make_guideline(title="Draft", status=Guideline.DRAFT)
        make_guideline(title="Romantic rubato", tags=("romantic",))
        make_guideline(title="Private", visibility=Guideline.PRIVATE)
        specs = services.resolve_guidelines(["fugue", "Baroque"])
        self.assertEqual([s.title for s in specs], ["Baroque: detached touch"])
        self.assertEqual(len(specs[0].rubrics), 1)
        self.assertEqual(services.resolve_guidelines([]), [])

    def test_score_tags_resolve(self):
        score = make_score(composed_date="1722")
        make_guideline()
        titles = [s.title for s in services.resolve_guidelines(services.tags_for_score(score.pk))]
        self.assertEqual(titles, ["Baroque: detached touch"])
        self.assertEqual(services.tags_for_score(999999), [])


# --- Parser (Task 6) ----------------------------------------------------------

import json  # noqa: E402

from User_accounts import tokens  # noqa: E402

from .parsing import get_translator  # noqa: E402


class KeywordParserTests(TestCase):
    def parse(self, text):
        return get_translator().parse(text)

    def test_phrasings(self):
        cases = {
            "gaps between the notes is more then 0.5 sec": ("note_gap", "gt", 0.5, None, "sec", "all"),
            "at least 30% of the note silent between notes": ("note_gap", "gte", 30, None, "pct_of_note", "all"),
            "notes held under 70% of written length": ("sounding_ratio", "lt", 70, None, "pct_of_note", "all"),
            "gap between 0.2 and 0.4 s": ("note_gap", "between", 0.2, 0.4, "sec", "all"),
            "timing within 50 ms": ("onset_deviation", "lte", 50, None, "ms", "all"),
            "Gaps over 25% of a beat": ("note_gap", "gt", 25, None, "pct_of_beat", "all"),
            "staccato notes held at most 50%": ("sounding_ratio", "lte", 50, None, "pct_of_note", "staccato"),
            "dynamic range over 12 dB": ("volume_range", "gt", 12, None, "db", "all"),
        }
        for text, (metric, operator, value, value_max, unit, applies_to) in cases.items():
            with self.subTest(text=text):
                result = self.parse(text)
                self.assertEqual(result.missing, [])
                self.assertEqual(
                    result.rule,
                    {"metric": metric, "operator": operator, "value": value, "value_max": value_max,
                     "unit": unit, "applies_to": applies_to},
                )
                self.assertEqual(result.translator, "keyword")

    def test_spans_cover_what_was_understood(self):
        text = "gaps between the notes is more then 0.5 sec"
        roles = {role: text[start:end] for start, end, role in self.parse(text).matched_spans}
        self.assertEqual(roles, {"metric": "gaps", "comparator": "more then", "value": "0.5", "unit": "sec"})

    def test_unparseable_text_returns_no_rule(self):
        for text, missing in (
            ("play it nicely", ["metric", "comparator", "value"]),
            ("gaps more than 0.5", ["unit"]),
            ("timing within 50", ["unit"]),
            ("gaps should be big", ["comparator", "value"]),
        ):
            with self.subTest(text=text):
                result = self.parse(text)
                self.assertIsNone(result.rule)
                self.assertEqual(result.missing, missing)
                self.assertTrue(result.message)
        self.assertIn("nicely", self.parse("play it nicely").unrecognised)

    def test_unit_that_does_not_fit_the_metric(self):
        result = self.parse("dynamic range over 3 sec")
        self.assertIsNone(result.rule)
        self.assertIn("can't be measured", result.message)


# --- API (Tasks 6-7) ----------------------------------------------------------


class ApiTestCase(TestCase):
    def setUp(self):
        self.admin = make_user("admin@x.co", staff=True)
        self.contributor = make_user("c@x.co", contributor=True)
        self.other_contributor = make_user("d@x.co", contributor=True)
        self.player = make_user("p@x.co")
        self.tokens = {u: tokens.issue(u) for u in (self.admin, self.contributor, self.other_contributor, self.player)}

    def call(self, method, url, body=None, user=None):
        headers = {"HTTP_AUTHORIZATION": f"Bearer {self.tokens[user]}"} if user else {}
        kwargs = {"content_type": "application/json"}
        if body is not None:
            kwargs["data"] = json.dumps(body)
        return getattr(self.client, method)(url, **kwargs, **headers)

    def payload(self, **overrides):
        body = {
            "title": "Baroque: detached touch",
            "body": "Notes should be highly detached in this era.",
            "tags": ["Baroque", "bach"],
            "status": "published",
            "rubrics": [
                {"label": "Detached", "source_text": "gaps between the notes is more then 0.5 sec",
                 "metric": "note_gap", "operator": "gt", "value": 0.5, "unit": "sec"}
            ],
        }
        body.update(overrides)
        return body


class ParseEndpointTests(ApiTestCase):
    url = "/api/guidelines/rubrics/parse"

    def test_roles(self):
        body = {"text": "gaps between the notes is more then 0.5 sec"}
        self.assertEqual(self.call("post", self.url, body).status_code, 401)
        self.assertEqual(self.call("post", self.url, body, self.player).status_code, 403)
        response = self.call("post", self.url, body, self.contributor)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(
            {k: data["rule"][k] for k in ("metric", "operator", "value", "unit")},
            {"metric": "note_gap", "operator": "gt", "value": 0.5, "unit": "sec"},
        )
        self.assertEqual(data["matched_spans"][0]["role"], "metric")

    def test_bad_input(self):
        self.assertEqual(self.call("post", self.url, {"text": ""}, self.admin).status_code, 400)
        self.assertEqual(self.call("post", self.url, {"text": "x" * 501}, self.admin).status_code, 400)


class GuidelineApiTests(ApiTestCase):
    def create(self, user=None, **overrides):
        return self.call("post", "/api/guidelines", self.payload(**overrides), user or self.contributor)

    def test_create_needs_an_author(self):
        self.assertEqual(self.call("post", "/api/guidelines", self.payload()).status_code, 401)
        self.assertEqual(self.create(self.player).status_code, 403)
        response = self.create()
        self.assertEqual(response.status_code, 201)
        guideline = response.json()["guideline"]
        self.assertEqual(guideline["tags"], ["bach", "baroque"])
        self.assertEqual(guideline["rubrics"][0]["metric"], "note_gap")
        self.assertTrue(guideline["editable"])
        self.assertEqual(Guideline.objects.get().owner, self.contributor)
        self.assertEqual(Tag.objects.get(slug="baroque").kind, Tag.ERA)

    def test_invalid_rubric_is_400_with_field_messages(self):
        response = self.create(rubrics=[{"metric": "volume_range", "operator": "gt", "value": 1, "unit": "sec"}])
        self.assertEqual(response.status_code, 400)
        self.assertIn("rubrics[0].unit", response.json()["fields"])
        for overrides in (
            {"title": ""}, {"title": "x" * 201}, {"tags": ["ok"] * 21}, {"tags": ["!!"]},
            {"rubrics": [{}] * 21}, {"status": "live"}, {"visibility": "private"},
            {"rubrics": [{"metric": "note_gap", "operator": "between", "value": 1, "unit": "ms"}]},
            {"rubrics": [{"metric": "note_gap", "operator": "gt", "value": "1", "unit": "ms"}]},
        ):
            with self.subTest(overrides=overrides):
                self.assertEqual(self.create(**overrides).status_code, 400)
        self.assertFalse(Guideline.objects.exists())

    def test_ownership(self):
        guideline_id = self.create().json()["guideline"]["id"]
        url = f"/api/guidelines/{guideline_id}"
        self.assertEqual(self.call("put", url, {"title": "Mine now"}, self.other_contributor).status_code, 403)
        self.assertEqual(self.call("delete", url, None, self.other_contributor).status_code, 403)
        self.assertEqual(self.call("put", url, {"title": "Edited"}, self.player).status_code, 403)
        response = self.call("put", url, {"title": "Edited"}, self.contributor)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["guideline"]["version"], 2)
        self.assertEqual(self.call("put", url, {"title": "By admin"}, self.admin).json()["guideline"]["version"], 3)
        self.assertEqual(self.call("delete", url, None, self.admin).status_code, 204)
        self.assertFalse(Guideline.objects.exists())

    def test_update_keeps_rubric_ids_and_drops_removed_ones(self):
        created = self.create(rubrics=self.payload()["rubrics"] * 2).json()["guideline"]
        first, second = created["rubrics"]
        kept = {**first, "value": 0.3}
        response = self.call("put", f"/api/guidelines/{created['id']}", {"rubrics": [kept]}, self.contributor)
        (rubric,) = response.json()["guideline"]["rubrics"]
        self.assertEqual((rubric["id"], rubric["value"]), (first["id"], 0.3))
        self.assertFalse(Rubric.objects.filter(pk=second["id"]).exists())

    def test_drafts_are_hidden_from_players(self):
        draft_id = self.create(status="draft").json()["guideline"]["id"]
        self.create(title="Published")
        titles = [g["title"] for g in self.call("get", "/api/guidelines").json()["guidelines"]]
        self.assertEqual(titles, ["Published"])
        self.assertEqual(self.call("get", f"/api/guidelines/{draft_id}").status_code, 404)
        self.assertEqual(self.call("get", f"/api/guidelines/{draft_id}", user=self.other_contributor).status_code, 404)
        self.assertEqual(self.call("get", f"/api/guidelines/{draft_id}", user=self.contributor).status_code, 200)
        mine = self.call("get", "/api/guidelines?mine=1", user=self.contributor).json()["guidelines"]
        self.assertEqual(len(mine), 2)
        everything = self.call("get", "/api/guidelines?all=1", user=self.admin).json()["guidelines"]
        self.assertEqual(len(everything), 2)
        self.assertEqual(len(self.call("get", "/api/guidelines?tags=bach").json()["guidelines"]), 1)
        self.assertEqual(len(self.call("get", "/api/guidelines?tags=romantic").json()["guidelines"]), 0)

    def test_for_score(self):
        self.create()
        score = make_score(composer="Anon", composed_date="1722")
        data = self.call("get", f"/api/guidelines/for-score/{score.pk}").json()
        self.assertEqual(data["tags"], ["baroque"])
        self.assertEqual([g["title"] for g in data["guidelines"]], ["Baroque: detached touch"])
        self.assertEqual(self.call("get", "/api/guidelines/for-score/99999").json()["guidelines"], [])

    def test_tags_and_vocabulary(self):
        self.create()
        self.assertIn({"slug": "baroque", "kind": "era"}, self.call("get", "/api/guidelines/tags").json()["tags"])
        vocabulary = self.call("get", "/api/guidelines/vocabulary").json()
        self.assertIn("note_gap", [m["name"] for m in vocabulary["metrics"]])
        self.assertIn("between", vocabulary["operators"])

    def test_score_tags_patch(self):
        score = make_score(composer="Anon")
        url = f"/api/scores/{score.pk}/tags"
        body = {"tags": ["Fugue"], "composed_date": "1722"}
        self.assertEqual(self.call("patch", url, body).status_code, 401)
        self.assertEqual(self.call("patch", url, body, self.player).status_code, 403)
        response = self.call("patch", url, body, self.contributor)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(sorted(response.json()["score"]["tags"]), ["baroque", "fugue"])
        self.assertEqual(self.call("patch", "/api/scores/99999/tags", body, self.admin).status_code, 404)
        self.assertEqual(self.call("patch", url, {"tags": "fugue"}, self.admin).status_code, 400)

    def test_me_includes_roles(self):
        for user, roles in ((self.admin, ["admin"]), (self.contributor, ["contributor"]), (self.player, [])):
            with self.subTest(user=user.email):
                self.assertEqual(self.call("get", "/api/auth/me", user=user).json()["user"]["roles"], roles)
