"""Tests for what stands between the internet and the backend: production
settings, the health check, the app key, the rate limit, /storage/, and the
quiz route.

Run with:  python manage.py test server

None of these touch the database. Most use the small URL config at the bottom
of this file so they don't depend on the audio stack; `RealUrlConfTests` runs
the real `server.urls` and so needs the full production requirements.
"""

import tempfile
import time
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured
from django.http import HttpResponse, JsonResponse
from django.test import Client, RequestFactory, SimpleTestCase, override_settings
from django.urls import path, re_path

from server.config import build_settings
from server.middleware import RateLimiter

PROD = {
    "DJANGO_ENV": "production",
    "DJANGO_SECRET_KEY": "a-real-secret",
    "ALLOWED_HOSTS": "api.example.com",
    "APP_API_KEY": "app-key",
    "SUPPORT_EMAIL": "help@example.org",
}


class ConfigTests(SimpleTestCase):
    """build_settings(env) turns the environment into the values settings.py uses.
    It is separate from settings.py so it can be tested without re-importing it."""

    def test_with_nothing_set_it_is_exactly_the_old_development_setup(self):
        cfg = build_settings({})
        self.assertIs(cfg["IS_PRODUCTION"], False)
        self.assertIs(cfg["DEBUG"], True)
        self.assertEqual(cfg["SECRET_KEY"], "dev-secret-key-change-in-production")
        self.assertEqual(cfg["ALLOWED_HOSTS"], ["*"])
        self.assertIsNone(cfg["SECURE_PROXY_SSL_HEADER"])
        self.assertEqual(cfg["APP_API_KEY"], "")

    def test_development_still_honours_the_old_variables(self):
        cfg = build_settings({"DEBUG": "False", "DJANGO_SECRET_KEY": "mine"})
        self.assertIs(cfg["DEBUG"], False)
        self.assertEqual(cfg["SECRET_KEY"], "mine")

    def test_development_has_no_rate_limit_unless_asked(self):
        cfg = build_settings({})
        self.assertEqual(cfg["RATE_LIMIT_HUM_PER_MINUTE"], 0)
        self.assertEqual(cfg["RATE_LIMIT_DEFAULT_PER_MINUTE"], 0)
        cfg = build_settings({"RATE_LIMIT_HUM_PER_MINUTE": "5"})
        self.assertEqual(cfg["RATE_LIMIT_HUM_PER_MINUTE"], 5)

    def test_production_switch_by_django_env(self):
        self.assertIs(build_settings(PROD)["IS_PRODUCTION"], True)

    def test_production_switch_by_cloud_run(self):
        # Cloud Run sets K_SERVICE in every container it starts.
        env = {k: v for k, v in PROD.items() if k != "DJANGO_ENV"} | {"K_SERVICE": "hu-accompany"}
        self.assertIs(build_settings(env)["IS_PRODUCTION"], True)

    def test_production_is_never_in_debug_mode(self):
        self.assertIs(build_settings(PROD | {"DEBUG": "True"})["DEBUG"], False)

    def test_production_trusts_the_proxys_https_header(self):
        self.assertEqual(build_settings(PROD)["SECURE_PROXY_SSL_HEADER"], ("HTTP_X_FORWARDED_PROTO", "https"))

    def test_production_reads_hosts_from_a_comma_list(self):
        cfg = build_settings(PROD | {"ALLOWED_HOSTS": " api.example.com , b.example.com ,"})
        self.assertEqual(cfg["ALLOWED_HOSTS"], ["api.example.com", "b.example.com"])

    def test_production_refuses_to_start_without_a_real_secret_key(self):
        without = {k: v for k, v in PROD.items() if k != "DJANGO_SECRET_KEY"}
        with self.assertRaisesMessage(ImproperlyConfigured, "DJANGO_SECRET_KEY"):
            build_settings(without)
        with self.assertRaisesMessage(ImproperlyConfigured, "DJANGO_SECRET_KEY"):
            build_settings(PROD | {"DJANGO_SECRET_KEY": "dev-secret-key-change-in-production"})

    def test_production_refuses_to_start_without_allowed_hosts(self):
        without = {k: v for k, v in PROD.items() if k != "ALLOWED_HOSTS"}
        with self.assertRaisesMessage(ImproperlyConfigured, "ALLOWED_HOSTS"):
            build_settings(without)
        with self.assertRaisesMessage(ImproperlyConfigured, "ALLOWED_HOSTS"):
            build_settings(PROD | {"ALLOWED_HOSTS": "*"})

    def test_production_refuses_to_start_without_an_app_key(self):
        without = {k: v for k, v in PROD.items() if k != "APP_API_KEY"}
        with self.assertRaisesMessage(ImproperlyConfigured, "APP_API_KEY"):
            build_settings(without)

    def test_production_has_rate_limits_by_default_and_they_can_be_changed(self):
        cfg = build_settings(PROD)
        self.assertGreater(cfg["RATE_LIMIT_HUM_PER_MINUTE"], 0)
        self.assertGreater(cfg["RATE_LIMIT_DEFAULT_PER_MINUTE"], cfg["RATE_LIMIT_HUM_PER_MINUTE"])
        self.assertEqual(build_settings(PROD | {"RATE_LIMIT_HUM_PER_MINUTE": "7"})["RATE_LIMIT_HUM_PER_MINUTE"], 7)

    def test_the_legal_pages_have_sensible_development_defaults(self):
        cfg = build_settings({})
        self.assertEqual(cfg["LEGAL_PUBLISHER"], "AG")
        self.assertEqual(cfg["HUM_TTL_HOURS"], 3.0)
        self.assertTrue(cfg["SUPPORT_EMAIL"].endswith(".invalid"))  # visibly a placeholder, never a real address

    def test_accounts_and_talk_mode_are_off_in_production_unless_switched_on(self):
        # The same defaults as the app's build switches, so the pages describe the app people download.
        cfg = build_settings(PROD)
        self.assertEqual((cfg["LOGIN_REQUIRED"], cfg["TALK_MODE"]), (False, False))
        cfg = build_settings(PROD | {"LOGIN_REQUIRED": "true", "TALK_MODE": "True"})
        self.assertEqual((cfg["LOGIN_REQUIRED"], cfg["TALK_MODE"]), (True, True))

    def test_a_development_server_keeps_talk_mode_unless_told_otherwise(self):
        self.assertIs(build_settings({})["TALK_MODE"], True)
        self.assertIs(build_settings({"TALK_MODE": "false"})["TALK_MODE"], False)
        self.assertIs(build_settings({})["LOGIN_REQUIRED"], False)

    def test_the_legal_pages_settings_can_be_changed(self):
        cfg = build_settings({"LEGAL_PUBLISHER": "Someone Else", "SUPPORT_EMAIL": "me@example.org", "HUM_TTL_HOURS": "1.5"})
        self.assertEqual((cfg["LEGAL_PUBLISHER"], cfg["SUPPORT_EMAIL"], cfg["HUM_TTL_HOURS"]), ("Someone Else", "me@example.org", 1.5))

    def test_production_will_not_start_with_a_missing_or_placeholder_support_address(self):
        # The address is published in the privacy policy that App Review reads. A placeholder must never get there.
        without = {k: v for k, v in PROD.items() if k != "SUPPORT_EMAIL"}
        for bad in (None, "", "not-an-address", "support@hu-accompany.invalid", "support@hu-accompany.example"):
            env = dict(without) if bad is None else {**without, "SUPPORT_EMAIL": bad}
            with self.assertRaisesMessage(ImproperlyConfigured, "SUPPORT_EMAIL"):
                build_settings(env)

    def test_a_retention_that_is_not_a_positive_number_is_reported_by_name(self):
        for bad in ("lots", "0", "-2"):
            with self.assertRaisesMessage(ImproperlyConfigured, "HUM_TTL_HOURS"):
                build_settings({"HUM_TTL_HOURS": bad})

    def test_a_rate_limit_that_is_not_a_number_is_reported_by_name(self):
        with self.assertRaisesMessage(ImproperlyConfigured, "RATE_LIMIT_HUM_PER_MINUTE"):
            build_settings(PROD | {"RATE_LIMIT_HUM_PER_MINUTE": "lots"})


class RateLimiterTests(SimpleTestCase):
    def setUp(self):
        self.now = 1000.0
        self.limiter = RateLimiter(clock=lambda: self.now, window=60.0)

    def test_allows_up_to_the_limit_then_says_how_long_to_wait(self):
        self.assertEqual([self.limiter.check("a", 3) for _ in range(3)], [0.0, 0.0, 0.0])
        self.now += 10
        self.assertAlmostEqual(self.limiter.check("a", 3), 50.0)

    def test_the_window_slides(self):
        for _ in range(3):
            self.limiter.check("a", 3)
        self.now += 61
        self.assertEqual(self.limiter.check("a", 3), 0.0)

    def test_clients_do_not_share_a_budget(self):
        for _ in range(3):
            self.limiter.check("a", 3)
        self.assertGreater(self.limiter.check("a", 3), 0)
        self.assertEqual(self.limiter.check("b", 3), 0.0)

    def test_a_rejected_request_does_not_extend_the_wait(self):
        for _ in range(3):
            self.limiter.check("a", 3)
        self.now += 50
        for _ in range(10):  # refused, late in the window
            self.assertGreater(self.limiter.check("a", 3), 0)
        self.now += 11  # 61 s after the three allowed hits, 11 s after the refused ones
        self.assertEqual(self.limiter.check("a", 3), 0.0)

    def test_a_limit_of_zero_means_unlimited(self):
        self.assertTrue(all(self.limiter.check("a", 0) == 0.0 for _ in range(100)))

    def test_memory_is_bounded_when_many_clients_come_and_go(self):
        small = RateLimiter(clock=lambda: self.now, window=60.0, max_keys=50)
        for i in range(500):
            small.check(f"client-{i}", 5)
            self.now += 1
        self.assertLessEqual(len(small), 50 + 60)  # only clients seen inside the window can remain


def _ok(request, *args, **kwargs):
    return JsonResponse({"ok": True})


urlpatterns = [
    path("api/ping", _ok),
    path("api/hum/ping", _ok),
    path("api/hum/talk/speech/<str:reply_id>", _ok),
]

GATE = [
    "server.middleware.HealthCheckMiddleware",
    "server.middleware.RateLimitMiddleware",
    "server.middleware.AppKeyMiddleware",
]
# With Django's own middleware behind it, which is what refuses unknown Host headers.
CHAIN = GATE + ["django.middleware.common.CommonMiddleware"]


@override_settings(ROOT_URLCONF="server.tests", MIDDLEWARE=CHAIN, APP_API_KEY="", ALLOWED_HOSTS=["testserver"],
                   RATE_LIMIT_HUM_PER_MINUTE=0, RATE_LIMIT_DEFAULT_PER_MINUTE=0)
class MiddlewareTests(SimpleTestCase):
    def fresh_client(self):
        return Client()  # a new client loads the middleware chain with the current settings

    # -- health check --------------------------------------------------------
    def test_healthz_answers_without_a_key_and_from_any_host(self):
        with override_settings(APP_API_KEY="secret"):
            response = self.fresh_client().get("/healthz", HTTP_HOST="10.1.2.3")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"ok")

    def test_healthz_is_never_rate_limited(self):
        with override_settings(RATE_LIMIT_DEFAULT_PER_MINUTE=1):
            c = self.fresh_client()
            self.assertTrue(all(c.get("/healthz").status_code == 200 for _ in range(5)))

    def test_other_routes_do_refuse_an_unknown_host_so_the_health_pass_means_something(self):
        self.assertEqual(self.fresh_client().get("/api/ping", HTTP_HOST="10.1.2.3").status_code, 400)

    # -- app key --------------------------------------------------------------
    def test_without_a_configured_key_everything_is_open(self):
        self.assertEqual(self.fresh_client().get("/api/ping").status_code, 200)

    def test_requests_need_the_right_key(self):
        with override_settings(APP_API_KEY="secret"):
            c = self.fresh_client()
            missing = c.get("/api/ping")
            wrong = c.get("/api/ping", HTTP_X_APP_KEY="nope")
            right = c.get("/api/ping", HTTP_X_APP_KEY="secret")
        self.assertEqual((missing.status_code, wrong.status_code, right.status_code), (401, 401, 200))
        self.assertEqual(missing.json()["code"], "unauthorized")
        self.assertIn("error", missing.json())  # the app shows this text to the user

    def test_a_key_with_odd_characters_is_a_401_not_a_crash(self):
        with override_settings(APP_API_KEY="secret"):
            response = self.fresh_client().get("/api/ping", HTTP_X_APP_KEY="sécret☃")
        self.assertEqual(response.status_code, 401)

    def test_audio_playback_urls_work_without_a_header_but_only_for_get(self):
        # An audio player fetches the spoken reply itself and cannot send our header.
        # The reply id is 96 random bits and expires, so the URL is the credential.
        with override_settings(APP_API_KEY="secret"):
            c = self.fresh_client()
            self.assertEqual(c.get("/api/hum/talk/speech/abc123").status_code, 200)
            self.assertEqual(c.post("/api/hum/talk/speech/abc123").status_code, 401)

    def test_the_public_pages_need_no_key_but_only_for_reading(self):
        # App Review, and anyone tapping "Privacy Policy" before signing up, must be able to read them.
        with override_settings(APP_API_KEY="secret"):
            c = self.fresh_client()
            for name in ("privacy", "terms", "support"):
                self.assertEqual(c.get(f"/{name}").status_code, 200, name)
                self.assertEqual(c.get(f"/{name}/").status_code, 200, name)
                self.assertEqual(c.head(f"/{name}").status_code, 200, name)
                self.assertEqual(c.post(f"/{name}").status_code, 401, name)
            self.assertEqual(c.get("/privacy/other").status_code, 401)
            self.assertEqual(c.get("/privacyx").status_code, 401)
            self.assertEqual(c.get("/api/ping").status_code, 401)

    def test_the_public_pages_are_still_rate_limited(self):
        with override_settings(APP_API_KEY="secret", RATE_LIMIT_DEFAULT_PER_MINUTE=2):
            c = self.fresh_client()
            self.assertEqual([c.get("/terms").status_code for _ in range(3)], [200, 200, 429])

    # -- rate limit -----------------------------------------------------------
    def test_hum_routes_have_their_own_tighter_limit(self):
        with override_settings(RATE_LIMIT_HUM_PER_MINUTE=2, RATE_LIMIT_DEFAULT_PER_MINUTE=100):
            c = self.fresh_client()
            codes = [c.get("/api/hum/ping").status_code for _ in range(3)]
            other = c.get("/api/ping").status_code
        self.assertEqual(codes, [200, 200, 429])
        self.assertEqual(other, 200)

    def test_the_default_limit_covers_other_routes(self):
        with override_settings(RATE_LIMIT_DEFAULT_PER_MINUTE=2):
            c = self.fresh_client()
            self.assertEqual([c.get("/api/ping").status_code for _ in range(3)], [200, 200, 429])

    def test_a_429_says_when_to_retry(self):
        with override_settings(RATE_LIMIT_DEFAULT_PER_MINUTE=1):
            c = self.fresh_client()
            c.get("/api/ping")
            response = c.get("/api/ping")
        self.assertEqual(response.status_code, 429)
        self.assertGreaterEqual(int(response["Retry-After"]), 1)
        self.assertEqual(response.json()["code"], "rate_limited")
        self.assertIn("error", response.json())

    def test_clients_are_told_apart_by_the_address_the_proxy_appended(self):
        # Only the LAST X-Forwarded-For entry is added by the proxy; earlier ones are
        # whatever the caller wrote, so rotating them must not buy a fresh budget.
        with override_settings(RATE_LIMIT_DEFAULT_PER_MINUTE=1):
            c = self.fresh_client()
            first = c.get("/api/ping", HTTP_X_FORWARDED_FOR="1.1.1.1, 9.9.9.9")
            spoofed = c.get("/api/ping", HTTP_X_FORWARDED_FOR="2.2.2.2, 9.9.9.9")
            someone_else = c.get("/api/ping", HTTP_X_FORWARDED_FOR="3.3.3.3, 8.8.8.8")
        self.assertEqual((first.status_code, spoofed.status_code, someone_else.status_code), (200, 429, 200))

    def test_guessing_keys_is_throttled_before_the_key_is_even_checked(self):
        with override_settings(APP_API_KEY="secret", RATE_LIMIT_DEFAULT_PER_MINUTE=2):
            c = self.fresh_client()
            codes = [c.get("/api/ping", HTTP_X_APP_KEY="guess").status_code for _ in range(3)]
        self.assertEqual(codes, [401, 401, 429])


class StorageViewTests(SimpleTestCase):
    """/storage/ serves files by URL with no key and no listing of who may read them:
    right for local development, wrong on the internet (it holds feedback files)."""

    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        (Path(self.root.name) / "storage").mkdir()
        (Path(self.root.name) / "storage" / "hello.txt").write_text("hi")
        self.request = RequestFactory().get("/storage/hello.txt")

    def view(self, debug):
        from server.views import storage
        with override_settings(BASE_DIR=Path(self.root.name), DEBUG=debug):
            return storage(self.request, "hello.txt")

    def test_it_is_a_404_when_not_debugging(self):
        from django.http import Http404
        with self.assertRaises(Http404):
            self.view(debug=False)

    def test_it_still_serves_files_in_development(self):
        response = self.view(debug=True)
        self.assertEqual(b"".join(response.streaming_content), b"hi")


@override_settings(ROOT_URLCONF="api.urls", MIDDLEWARE=[])
class QuizRouteTests(SimpleTestCase):
    def test_the_quiz_routes_exist(self):
        c = Client()
        response = c.post("/api/quiz/generate", {"topic": "baroque", "length": 5, "seed": 1}, content_type="application/json")
        self.assertEqual(response.status_code, 200, response.content)
        self.assertEqual(len(response.json()["questions"]), 5)
        self.assertEqual(c.get("/api/quiz/topics").status_code, 200)

    def test_the_existing_api_routes_are_still_there(self):
        response = Client().post("/api/feedback/phrase", "not json", content_type="application/json")
        self.assertEqual(response.status_code, 400)


@override_settings(ALLOWED_HOSTS=["testserver"], APP_API_KEY="secret", DEBUG=False,
                   RATE_LIMIT_HUM_PER_MINUTE=0, RATE_LIMIT_DEFAULT_PER_MINUTE=0)
class RealUrlConfTests(SimpleTestCase):
    """The actual server.urls and the middleware list in settings.py, together."""

    def test_settings_put_the_gate_in_front_of_everything(self):
        from django.conf import settings
        self.assertEqual(list(settings.MIDDLEWARE), CHAIN)

    def test_the_health_check_works_with_no_key(self):
        self.assertEqual(Client().get("/healthz").status_code, 200)

    def test_a_real_route_is_closed_without_the_key_and_open_with_it(self):
        c = Client()
        self.assertEqual(c.get("/api/scores/search?q=bach").status_code, 401)
        self.assertEqual(c.get("/api/quiz/topics", HTTP_X_APP_KEY="secret").status_code, 200)

    def test_the_legal_pages_are_public_on_the_real_server(self):
        c = Client()
        for name, words in (("privacy", "Privacy Policy"), ("terms", "Terms of Service"), ("support", "Support")):
            response = c.get(f"/{name}")  # note: no key
            self.assertEqual(response.status_code, 200, name)
            self.assertIn(words, response.content.decode(), name)

    def test_storage_is_not_served_in_production_even_with_the_key(self):
        self.assertEqual(Client().get("/storage/feedback/x.json", HTTP_X_APP_KEY="secret").status_code, 404)


class JanitorTests(SimpleTestCase):
    """server/janitor.py clears out old hum files. On Cloud Run the container's disk is
    memory, so without this every hum would stay in RAM until the instance ran out."""

    def setUp(self):
        import os
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "hum_data"
        (self.root / "uploads").mkdir(parents=True)
        self.now = time.time()
        self.os = os

    def make(self, relative, age_hours):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x")
        stamp = self.now - age_hours * 3600
        self.os.utime(path, (stamp, stamp))
        return path

    def sweep(self, max_age_hours=3):
        from server.janitor import sweep
        return sweep(self.root, max_age_seconds=max_age_hours * 3600, now=self.now)

    def test_old_files_go_and_recent_ones_stay(self):
        old = self.make("uploads/old.wav", age_hours=5)
        recent = self.make("uploads/recent.wav", age_hours=1)
        self.assertEqual(self.sweep(), 1)
        self.assertFalse(old.exists())
        self.assertTrue(recent.exists())

    def test_folders_left_empty_are_removed_once_they_too_are_old_but_never_the_root(self):
        self.make("runs/run1/step/out.json", age_hours=9)
        self.make("runs/run2/out.json", age_hours=0.5)
        self.sweep()  # the old file goes; the folders it leaves were only just changed, so they stay
        self.assertTrue((self.root / "runs" / "run2" / "out.json").exists())
        self.now += 4 * 3600  # later: the empty folders are now old as well
        self.sweep()
        self.assertFalse((self.root / "runs" / "run1").exists())
        self.make("uploads/a.wav", age_hours=9)
        self.sweep()
        self.assertTrue(self.root.exists())

    def test_a_folder_that_was_only_just_created_is_left_alone(self):
        # The hum engine makes a run folder and writes into it a moment later. Removing it in
        # between breaks that upload (seen in a rehearsal: "No such file ... intake_log.json").
        fresh = self.root / "runs" / "run-in-progress"
        fresh.mkdir(parents=True)
        self.sweep()
        self.assertTrue(fresh.is_dir())

    def test_a_folder_with_a_recent_file_keeps_its_old_files_company(self):
        # Only age decides, per file; a run folder is not deleted as a unit.
        old = self.make("runs/r/old.json", age_hours=9)
        self.make("runs/r/new.json", age_hours=0.1)
        self.sweep()
        self.assertFalse(old.exists())
        self.assertTrue((self.root / "runs" / "r" / "new.json").exists())

    def test_it_does_not_follow_a_symlink_out_of_the_folder(self):
        outside = Path(self.tmp.name) / "precious"
        outside.mkdir()
        keep = outside / "keep.txt"
        keep.write_text("do not delete")
        self.os.utime(keep, (self.now - 99 * 3600,) * 2)
        (self.root / "link").symlink_to(outside, target_is_directory=True)
        self.sweep()
        self.assertTrue(keep.exists())

    def test_a_missing_folder_is_not_an_error(self):
        from server.janitor import sweep
        self.assertEqual(sweep(Path(self.tmp.name) / "nope", max_age_seconds=1, now=self.now), 0)

    def test_it_refuses_dangerous_roots(self):
        from server.janitor import sweep
        for bad in (Path("/"), Path.home(), Path("/tmp"), Path("relative/path")):
            with self.assertRaises(ValueError, msg=str(bad)):
                sweep(bad, max_age_seconds=1, now=self.now)

    def test_the_settings_come_from_the_environment(self):
        from server.janitor import settings_from_env
        root, max_age, interval = settings_from_env({"HUM_DATA_DIR": "/tmp/h/x", "HUM_TTL_HOURS": "2", "HUM_SWEEP_MINUTES": "5"})
        self.assertEqual((root, max_age, interval), (Path("/tmp/h/x"), 7200.0, 300.0))
        root, max_age, interval = settings_from_env({})
        self.assertEqual(max_age, 3 * 3600.0)


# ---- The public pages App Store review looks for: /privacy, /terms, /support ------------------------

from server import legal  # noqa: E402  (the routes for them join the tiny URL config at the top of this file)

urlpatterns += [re_path(rf"^{name}/?$", legal.page_view(name)) for name in legal.TITLES]

import re
from html.parser import HTMLParser

LEGAL_SETTINGS = dict(LEGAL_PUBLISHER="AG", SUPPORT_EMAIL="help@example.org", HUM_TTL_HOURS=3.0)
# Most page tests read the pages with every feature on, so every passage is checked; LaunchLegalPagesTests reads
# them as the first release ships (no accounts, no Talk mode).
ALL_FEATURES = dict(LOGIN_REQUIRED=True, TALK_MODE=True)
NO_FEATURES = dict(LOGIN_REQUIRED=False, TALK_MODE=False)


class _Outline(HTMLParser):
    """Collects what a page needs to be a sane web page, and checks tags are balanced."""

    VOID = {"meta", "link", "br", "hr", "img", "input"}

    def __init__(self):
        super().__init__()
        self.stack, self.problems, self.h1s, self.title, self.links, self.meta = [], [], 0, "", [], {}
        self.lang, self._in_title = None, False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "html":
            self.lang = a.get("lang")
        if tag == "h1":
            self.h1s += 1
        if tag == "a" and a.get("href"):
            self.links.append(a["href"])
        if tag == "meta" and a.get("name"):
            self.meta[a["name"]] = a.get("content", "")
        if tag == "title":
            self._in_title = True
        if tag not in self.VOID:
            self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag == "title":
            self._in_title = False
        if tag in self.VOID:
            return
        if not self.stack or self.stack[-1] != tag:
            self.problems.append(f"</{tag}> closes {self.stack[-1] if self.stack else 'nothing'}")
        else:
            self.stack.pop()

    def handle_data(self, data):
        if self._in_title:
            self.title += data


def outline(html):
    parser = _Outline()
    parser.feed(html)
    parser.close()
    if parser.stack:
        parser.problems.append(f"never closed: {parser.stack}")
    return parser


@override_settings(ROOT_URLCONF="server.tests", MIDDLEWARE=[], ALLOWED_HOSTS=["testserver"], **LEGAL_SETTINGS, **ALL_FEATURES)
class LegalPagesTests(SimpleTestCase):
    """The pages are plain HTML in backend/legal/, filled in from settings, so what they say about
    the publisher, the contact address and how long hums are kept can't drift from the server's setup."""

    PAGES = ("privacy", "terms", "support")

    def get(self, name, **extra):
        return self.client.get(f"/{name}", **extra)

    def text(self, name):
        response = self.get(name)
        self.assertEqual(response.status_code, 200, name)
        return response.content.decode()

    def test_every_page_is_served_as_html(self):
        for name in self.PAGES:
            response = self.get(name)
            self.assertEqual(response.status_code, 200, name)
            self.assertEqual(response["Content-Type"], "text/html; charset=utf-8", name)

    def test_a_trailing_slash_works_too(self):
        self.assertEqual(self.client.get("/privacy/").status_code, 200)

    def test_only_reading_is_allowed(self):
        self.assertEqual(self.client.head("/terms").status_code, 200)
        self.assertEqual(self.client.post("/terms").status_code, 405)

    def test_every_page_names_the_publisher_and_the_contact_address(self):
        for name in self.PAGES:
            html = self.text(name)
            self.assertIn("AG", html, name)
            self.assertIn("mailto:help@example.org", html, name)

    def test_nothing_is_left_unfilled(self):
        for name in self.PAGES:
            self.assertNotIn("{{", self.text(name), name)
            self.assertNotIn("example.invalid", self.text(name), name)

    def test_the_policy_and_terms_carry_their_effective_date(self):
        from server.legal import EFFECTIVE_DATE
        for name in ("privacy", "terms"):
            self.assertIn(EFFECTIVE_DATE, self.text(name), name)

    def test_the_hum_retention_stated_is_the_one_the_server_uses(self):
        for hours, said in ((3.0, "3 hours"), (1.0, "1 hour"), (1.5, "1.5 hours")):
            with override_settings(HUM_TTL_HOURS=hours):
                self.assertIn(said, self.text("privacy"), hours)

    def test_no_page_keeps_a_stale_hard_coded_retention(self):
        # With the setting at 7 hours, "3 hours" (the default) must not survive anywhere a person could read it.
        with override_settings(HUM_TTL_HOURS=7.0):
            for name in self.PAGES:
                self.assertNotIn("3 hours", self.text(name), name)
            self.assertIn("7 hours", self.text("privacy"))
            self.assertIn("7 hours", self.text("support"))

    def test_values_from_settings_cannot_inject_markup(self):
        with override_settings(SUPPORT_EMAIL="<script>alert(1)</script>@a.b", LEGAL_PUBLISHER="A&G <b>"):
            for name in self.PAGES:
                html = self.text(name)
                self.assertNotIn("<script>alert", html, name)
                self.assertIn("A&amp;G &lt;b&gt;", html, name)

    def test_browsers_are_told_not_to_guess_or_run_anything_but_our_styles(self):
        response = self.get("privacy")
        self.assertEqual(response["X-Content-Type-Options"], "nosniff")
        csp = response["Content-Security-Policy"]
        self.assertIn("default-src 'none'", csp)
        self.assertIn("frame-ancestors 'none'", csp)
        self.assertNotIn("script", csp)
        self.assertIn("public", response["Cache-Control"])

    def test_each_page_is_well_formed_and_works_on_a_phone(self):
        for name in self.PAGES:
            page = outline(self.text(name))
            self.assertEqual(page.problems, [], name)
            self.assertEqual(page.lang, "en", name)
            self.assertEqual(page.h1s, 1, name)
            self.assertIn("width=device-width", page.meta.get("viewport", ""), name)
            self.assertTrue(page.title.strip(), name)

    def test_the_pages_link_to_each_other_and_every_link_resolves(self):
        for name in self.PAGES:
            links = outline(self.text(name)).links
            for other in set(self.PAGES) - {name}:
                self.assertIn(f"/{other}", links, f"{name} should link to {other}")
            for link in links:
                if link.startswith("/"):
                    self.assertEqual(self.client.get(link).status_code, 200, f"{name} -> {link}")

    # -- what the policy says has to be true of the app ------------------------------------------------
    def test_the_policy_lists_everyone_user_data_is_sent_to(self):
        html = self.text("privacy")
        section = html.split("<h2>Who receives your information</h2>")[1].split("<h2>")[0]
        for processor in ("Google Cloud", "Neon", "Cloudflare", "ElevenLabs", "Google Gemini"):
            self.assertIn(f"<strong>{processor}</strong>", section, processor)

    def test_the_policy_covers_what_the_app_collects_and_what_it_does_not_do(self):
        html = self.text("privacy")
        for phrase in ("email address", "password", "microphone", "humming", "voice", "hashed",
                       "do not sell", "do not use", "advertising", "under 13", "HTTPS"):
            self.assertIn(phrase.lower(), html.lower(), phrase)

    def test_the_policy_tells_people_how_to_use_their_rights_in_the_app(self):
        html = self.text("privacy")
        for label in ("Settings", "Export my data", "Delete account"):
            self.assertIn(label, html, label)

    def test_the_wording_matches_the_buttons_the_app_really_has(self):
        settings_page = Path(__file__).resolve().parents[2] / "frontend/lib/features/settings/settings_page.dart"
        if not settings_page.is_file():
            self.skipTest("the Flutter app is not in this checkout (e.g. inside the Docker image)")
        source = settings_page.read_text()
        for label in ("Export my data", "Delete account", "Privacy Policy", "Terms of Service"):
            self.assertIn(f"'{label}'", source, f"the app no longer has a '{label}' button, so the pages are wrong")

    def test_the_policy_discloses_every_third_party_service_the_server_uses(self):
        requirements = Path(__file__).resolve().parents[1] / "requirements-prod.txt"
        if not requirements.is_file():
            self.skipTest("requirements-prod.txt not present")
        wanted = requirements.read_text().lower()
        html = self.text("privacy").lower()
        for package, said in (("elevenlabs", "elevenlabs"), ("google-genai", "gemini")):
            if package in wanted:
                self.assertIn(said, html, f"the server uses {package} but the policy does not say so")

    def test_the_terms_cover_what_apple_and_users_need(self):
        html = self.text("terms")
        for phrase in ("13", "Canada", "Apple", "delete your account", "as is", "public-domain", "automated",
                       "artificial intelligence"):
            self.assertIn(phrase.lower(), html.lower(), phrase)

    def test_the_terms_include_each_term_apple_requires_in_a_custom_licence(self):
        # Apple's minimum terms for an app that uses its own licence agreement instead of Apple's standard one.
        html = self.text("terms")
        for phrase in ("not Apple Inc.", "Apple is not a party", "Usage Rules in the Apple Media Services Terms",
                       "maintenance and support", "refund the purchase price", "product liability",
                       "infringes", "U.S. government embargo", "third-party terms", "third-party beneficiaries",
                       "Questions or complaints"):
            self.assertIn(phrase.lower(), html.lower(), phrase)

    def test_the_terms_credit_the_dataset_as_its_license_requires_and_describe_the_screening(self):
        # PDMX is CC BY 4.0: credit, link, and say that changes were made. And the library is screened, not "all public domain".
        html = self.text("terms")
        for phrase in ("PDMX", "CC BY 4.0", "doi.org/10.5281/zenodo.13763756", "creativecommons.org/licenses/by/4.0",
                       "Long et al", "we made changes", "we screen", "we will remove"):
            self.assertIn(phrase.lower(), html.lower(), phrase)

    def test_the_policy_is_plain_that_elevenlabs_may_keep_the_voice_recording(self):
        # ElevenLabs keeps speech-to-text audio and text by default; its no-retention mode is for enterprise customers.
        # Saying only "under its own terms" would understate that.
        html = self.text("privacy").lower()
        self.assertIn("may keep the voice recording", html)
        self.assertIn("no-retention setting", html)
        # Its Terms (section 4(d)) license it to use customer content, voice included, to improve its services and
        # develop new products, perpetually and irrevocably. People must be told that, not just "may keep".
        self.assertIn("improve its services", html)
        self.assertIn("cannot be withdrawn", html)

    def test_talk_mode_is_stated_to_be_for_adults_in_both_documents(self):
        # Google's and ElevenLabs' terms both bar services used by people under 18, so Talk mode is adults-only
        # and the pages must say so just as the permission box in the app does.
        for page in ("terms", "privacy"):
            html = self.text(page).lower()
            self.assertIn("talk mode is for people 18 or older", html, page)
            self.assertIn("require", html, page)

    def test_the_policy_names_who_to_contact_about_privacy(self):
        # Quebec's privacy law expects a named person responsible for privacy and a way to reach them.
        html = self.text("privacy")
        self.assertIn("person responsible for privacy", html.lower())

    def test_the_support_page_answers_the_common_questions(self):
        html = self.text("support")
        for phrase in ("Delete account", "Export my data", "microphone", "Settings"):
            self.assertIn(phrase.lower(), html.lower(), phrase)


@override_settings(ROOT_URLCONF="server.tests", MIDDLEWARE=[], ALLOWED_HOSTS=["testserver"], **LEGAL_SETTINGS, **NO_FEATURES)
class LaunchLegalPagesTests(SimpleTestCase):
    """The pages as the first release ships: no accounts and no Talk mode. App Review compares them with the app,
    so they must not send people to buttons it hides or name services it never uses."""

    PAGES = LegalPagesTests.PAGES

    def text(self, name):
        response = self.client.get(f"/{name}")
        self.assertEqual(response.status_code, 200, name)
        return response.content.decode()

    def test_every_combination_of_switches_renders_cleanly(self):
        for accounts in (False, True):
            for talk in (False, True):
                with override_settings(LOGIN_REQUIRED=accounts, TALK_MODE=talk):
                    for name in self.PAGES:
                        html = self.text(name)
                        self.assertNotIn("{{", html, (name, accounts, talk))
                        self.assertNotIn("}}", html, (name, accounts, talk))
                        self.assertEqual(outline(html).problems, [], (name, accounts, talk))

    def test_nothing_mentions_accounts_or_talk_mode(self):
        for name in self.PAGES:
            html = self.text(name)
            for gone in ("hashed", "your password", "Delete account", "Export my data", "sign-in token", "Talk mode", "Gemini",
                         "ElevenLabs", "18 or older"):
                self.assertNotIn(gone.lower(), html.lower(), f"{name} still says {gone!r}")

    def test_the_policy_says_there_are_no_accounts_and_still_names_who_runs_the_service(self):
        html = self.text("privacy")
        self.assertIn("there are no accounts", html.lower())
        section = html.split("<h2>Who receives your information</h2>")[1].split("<h2>")[0]
        for processor in ("Google Cloud", "Neon", "Cloudflare"):
            self.assertIn(f"<strong>{processor}</strong>", section, processor)
        for phrase in ("microphone", "humming", "do not sell", "advertising", "under 13", "HTTPS", "website"):
            self.assertIn(phrase.lower(), html.lower(), phrase)

    def test_the_pages_cover_the_mac_as_well_as_the_iphone(self):
        for name in ("privacy", "support"):
            self.assertIn("System Settings", self.text(name), name)

    def test_the_app_is_called_by_its_public_name(self):
        for name in self.PAGES:
            html = self.text(name)
            self.assertIn("Accompanist", html, name)
            self.assertNotIn("Accomponist", html, name)
