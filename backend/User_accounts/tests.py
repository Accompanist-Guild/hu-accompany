import json

from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.test import TestCase

from User_accounts.models import AuthToken
from User_accounts.views import MAX_FAILURES

User = get_user_model()


class AccountsApiTests(TestCase):
    def setUp(self):
        cache.clear()

    def post(self, path, body, token=None):
        headers = {"HTTP_AUTHORIZATION": f"Bearer {token}"} if token else {}
        return self.client.post(path, json.dumps(body), content_type="application/json", **headers)

    def register(self, email="Ada@Example.com", password="correct horse", name="Ada"):
        return self.post("/api/auth/register", {"email": email, "password": password, "name": name})

    def bearer(self, token):
        return {"HTTP_AUTHORIZATION": f"Bearer {token}"}

    def test_register_returns_a_token_and_the_profile(self):
        response = self.register()
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["user"]["email"], "ada@example.com")
        self.assertEqual(body["user"]["name"], "Ada")
        self.assertTrue(body["token"])

    def test_the_token_is_not_stored(self):
        token = self.register().json()["token"]
        self.assertFalse(AuthToken.objects.filter(key_hash=token).exists())

    def test_register_refuses_bad_input(self):
        cases = [
            ({"email": "nope", "password": "correct horse"}, "bad_email"),
            ({"email": "a@b.co", "password": "short"}, "bad_password"),
            ({"email": "a@b.co"}, "bad_password"),
            ({"email": "a@b.co", "password": "correct horse", "name": "x" * 200}, "bad_name"),
        ]
        for body, code in cases:
            with self.subTest(body=body):
                response = self.post("/api/auth/register", body)
                self.assertEqual(response.status_code, 400)
                self.assertEqual(response.json()["code"], code)

    def test_register_twice_with_the_same_email_conflicts(self):
        self.register()
        response = self.register(email="ada@example.com")
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.json()["code"], "email_taken")

    def test_login_and_me(self):
        self.register()
        response = self.post("/api/auth/login", {"email": " ADA@example.com ", "password": "correct horse"})
        self.assertEqual(response.status_code, 200)
        me = self.client.get("/api/auth/me", **self.bearer(response.json()["token"]))
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.json()["user"]["email"], "ada@example.com")

    def test_login_with_the_wrong_password_is_refused_without_saying_which_part(self):
        self.register()
        for email, password in (("ada@example.com", "wrong password"), ("nobody@example.com", "correct horse")):
            with self.subTest(email=email):
                response = self.post("/api/auth/login", {"email": email, "password": password})
                self.assertEqual(response.status_code, 401)
                self.assertEqual(response.json()["code"], "bad_credentials")

    def test_login_locks_out_after_repeated_failures(self):
        self.register()
        for _ in range(MAX_FAILURES):
            self.post("/api/auth/login", {"email": "ada@example.com", "password": "wrong password"})
        locked = self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"})
        self.assertEqual(locked.status_code, 429)

    def test_a_good_login_resets_the_failure_count(self):
        self.register()
        for _ in range(MAX_FAILURES - 1):
            self.post("/api/auth/login", {"email": "ada@example.com", "password": "wrong password"})
        self.assertEqual(self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"}).status_code, 200)
        self.post("/api/auth/login", {"email": "ada@example.com", "password": "wrong password"})
        self.assertEqual(self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"}).status_code, 200)

    def test_me_needs_a_valid_token(self):
        self.assertEqual(self.client.get("/api/auth/me").status_code, 401)
        self.assertEqual(self.client.get("/api/auth/me", **self.bearer("not-a-token")).status_code, 401)

    def test_logout_ends_only_that_device(self):
        self.register()
        first = self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"}).json()["token"]
        second = self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"}).json()["token"]
        self.assertEqual(self.post("/api/auth/logout", {}, token=first).status_code, 204)
        self.assertEqual(self.client.get("/api/auth/me", **self.bearer(first)).status_code, 401)
        self.assertEqual(self.client.get("/api/auth/me", **self.bearer(second)).status_code, 200)

    def test_export_holds_the_account(self):
        token = self.register().json()["token"]
        response = self.client.get("/api/auth/export", **self.bearer(token))
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body["account"]["email"], "ada@example.com")
        self.assertEqual(len(body["signed_in_devices"]), 1)
        self.assertNotIn("password", json.dumps(body))
        self.assertEqual(self.client.get("/api/auth/export").status_code, 401)

    def test_delete_removes_the_account_and_every_token(self):
        token = self.register().json()["token"]
        other = self.post("/api/auth/login", {"email": "ada@example.com", "password": "correct horse"}).json()["token"]
        response = self.client.delete("/api/auth/account", **self.bearer(token))
        self.assertEqual(response.status_code, 204)
        self.assertFalse(User.objects.filter(username="ada@example.com").exists())
        self.assertEqual(AuthToken.objects.count(), 0)
        self.assertEqual(self.client.get("/api/auth/me", **self.bearer(other)).status_code, 401)
        # the email can be used again
        self.assertEqual(self.register().status_code, 201)

    def test_delete_needs_a_token_and_the_right_method(self):
        self.assertEqual(self.client.delete("/api/auth/account").status_code, 401)
        token = self.register().json()["token"]
        self.assertEqual(self.client.get("/api/auth/account", **self.bearer(token)).status_code, 405)
