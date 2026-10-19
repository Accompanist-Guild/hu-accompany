"""GET /api/scores/<id>/musicxml when the MusicXML files live in object storage (Cloudflare R2)
instead of on this server's disk.

A real HTTP server on localhost stands in for R2. The Score lookup is faked so these tests
need no database.
"""

import json
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from django.test import RequestFactory, SimpleTestCase, override_settings

from scores import views

KEY = "musicxml/Qm123.musicxml"
BODY = b'<?xml version="1.0"?><score-partwise><part-list/></score-partwise>'


class FakeR2(BaseHTTPRequestHandler):
    files: dict = {}
    requested: list = []

    def do_GET(self):
        type(self).requested.append(self.path)
        if self.headers.get("User-Agent", "").startswith("Python-urllib"):
            # What Cloudflare's r2.dev addresses do to Python's default User-Agent.
            self.send_response(403)
            self.end_headers()
            return
        data = type(self).files.get(self.path.lstrip("/"))
        if data is None:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class RemoteMusicXmlTests(SimpleTestCase):
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), FakeR2)
        cls.base = f"http://127.0.0.1:{cls.server.server_address[1]}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.addClassCleanup(cls.server.server_close)
        cls.addClassCleanup(cls.server.shutdown)

    def setUp(self):
        FakeR2.files = {KEY: BODY}
        FakeR2.requested = []
        self.storage = tempfile.TemporaryDirectory()
        self.addCleanup(self.storage.cleanup)

    def get(self, musicxml_path=KEY, base=None, **extra):
        score = SimpleNamespace(musicxml_path=musicxml_path)
        with mock.patch.object(views, "Score") as Score, override_settings(
            STORAGE_ROOT=Path(self.storage.name), MUSICXML_BASE_URL=self.base if base is None else base, **extra
        ):
            Score.objects.filter.return_value.first.return_value = score
            return views.musicxml_view(RequestFactory().get("/api/scores/1/musicxml"), 1)

    def body(self, response):
        return b"".join(response.streaming_content) if response.streaming else response.content

    def test_a_file_on_this_servers_disk_is_served_from_disk_as_before(self):
        (Path(self.storage.name) / "musicxml").mkdir()
        (Path(self.storage.name) / KEY).write_bytes(b"local copy")
        response = self.get()
        self.assertEqual(self.body(response), b"local copy")
        self.assertEqual(FakeR2.requested, [], "must not ask R2 when the file is here")

    def test_without_the_file_or_a_storage_url_it_is_a_404_as_before(self):
        response = self.get(base="")
        self.assertEqual(response.status_code, 404)
        self.assertIn("missing", json.loads(response.content)["error"])

    def test_otherwise_it_is_fetched_from_object_storage(self):
        response = self.get()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.body(response), BODY)
        self.assertEqual(response["Content-Type"], "application/vnd.recordare.musicxml+xml")
        self.assertEqual(FakeR2.requested, ["/" + KEY])

    def test_a_trailing_slash_on_the_base_url_does_not_matter(self):
        self.assertEqual(self.get(base=self.base + "/").status_code, 200)

    def test_a_file_that_is_not_in_object_storage_is_a_404(self):
        FakeR2.files = {}
        response = self.get()
        self.assertEqual(response.status_code, 404)

    def test_object_storage_being_down_is_a_502_not_a_hang_or_a_crash(self):
        response = self.get(base="http://127.0.0.1:9")  # nothing listens on the discard port
        self.assertEqual(response.status_code, 502)
        self.assertEqual(json.loads(response.content)["code"], "storage_unavailable")

    def test_a_file_over_the_size_limit_is_refused(self):
        with mock.patch.object(views, "MAX_REMOTE_BYTES", 10):
            response = self.get()
        self.assertEqual(response.status_code, 502)

    def test_only_the_expected_kind_of_path_is_ever_requested(self):
        for bad in ("musicxml/../secret", "../etc/passwd", "http://evil.example/x.musicxml", "musicxml/a/b.musicxml", "other/Qm1.musicxml"):
            FakeR2.files = {bad.lstrip("/"): BODY}
            response = self.get(musicxml_path=bad)
            self.assertEqual(response.status_code, 404, bad)
        self.assertEqual(FakeR2.requested, [])

    def test_a_storage_url_that_is_not_http_is_a_configuration_error(self):
        response = self.get(base="file:///etc")
        self.assertEqual(response.status_code, 502)
        self.assertEqual(FakeR2.requested, [])

    def test_an_unknown_score_is_still_a_404(self):
        with mock.patch.object(views, "Score") as Score:
            Score.objects.filter.return_value.first.return_value = None
            response = views.musicxml_view(RequestFactory().get("/x"), 99)
        self.assertEqual(response.status_code, 404)
