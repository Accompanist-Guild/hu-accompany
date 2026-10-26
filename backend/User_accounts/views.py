"""Accounts over HTTP, mounted at /api/auth/ (see User_accounts/urls.py).

POST   /api/auth/register  JSON {email, password, name?} -> 201 {token, user}. 409 when the email has an account.
POST   /api/auth/login     JSON {email, password}        -> {token, user}. 401 when they don't match, 429 after too many tries.
POST   /api/auth/logout    Bearer token                  -> 204. Signs out this device only.
GET    /api/auth/me        Bearer token                  -> {user}. 401 when the token is no longer valid.
GET    /api/auth/export    Bearer token                  -> everything the server holds about the account, as JSON.
DELETE /api/auth/account   Bearer token                  -> 204. Deletes the account and signs out every device.

Errors are {error, code} with `error` worded for the person using the app.
"""

import json
import logging

from django.contrib.auth import authenticate, get_user_model
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.validators import validate_email
from django.http import HttpRequest, HttpResponse, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_GET, require_http_methods, require_POST

from guidelines.permissions import roles_of

from . import tokens

log = logging.getLogger(__name__)

User = get_user_model()

MIN_PASSWORD = 8
MAX_PASSWORD = 128
MAX_NAME = 80
# Wrong passwords tolerated per email before it is locked out for a while.
MAX_FAILURES = 5
LOCKOUT_SECONDS = 15 * 60


def error(message: str, status: int, code: str) -> JsonResponse:
    return JsonResponse({"error": message, "code": code}, status=status)


def read_json(request: HttpRequest) -> dict | None:
    try:
        data = json.loads(request.body or b"{}")
    except json.JSONDecodeError:
        return None
    return data if isinstance(data, dict) else None


def user_json(user) -> dict:
    return {
        "id": user.pk,
        "email": user.email,
        "name": user.first_name,
        "joined": user.date_joined.isoformat(),
        # "admin" / "contributor": who may author guidelines. The app only
        # uses this to show the Guides tab; the server checks it again.
        "roles": roles_of(user),
    }


def _clean_email(value) -> str | None:
    if not isinstance(value, str):
        return None
    email = value.strip().lower()
    try:
        validate_email(email)
    except ValidationError:
        return None
    return email


def _failures_key(email: str) -> str:
    return f"accounts:login-failures:{email}"


@csrf_exempt
@require_POST
def register(request: HttpRequest) -> HttpResponse:
    data = read_json(request)
    if data is None:
        return error("Send JSON with an email and a password.", 400, "bad_request")
    email = _clean_email(data.get("email"))
    password = data.get("password")
    name = data.get("name", "")
    if email is None:
        return error("That doesn't look like an email address.", 400, "bad_email")
    if not isinstance(password, str) or not MIN_PASSWORD <= len(password) <= MAX_PASSWORD:
        return error(f"Choose a password of at least {MIN_PASSWORD} characters.", 400, "bad_password")
    if not isinstance(name, str) or len(name.strip()) > MAX_NAME:
        return error("That name is too long.", 400, "bad_name")
    if User.objects.filter(username=email).exists():
        return error("An account with this email already exists. Try signing in.", 409, "email_taken")

    user = User.objects.create_user(username=email, email=email, password=password, first_name=name.strip())
    return JsonResponse({"token": tokens.issue(user), "user": user_json(user)}, status=201)


@csrf_exempt
@require_POST
def login(request: HttpRequest) -> HttpResponse:
    data = read_json(request)
    if data is None:
        return error("Send JSON with an email and a password.", 400, "bad_request")
    email = _clean_email(data.get("email"))
    password = data.get("password")
    wrong = error("That email and password don't match.", 401, "bad_credentials")
    if email is None or not isinstance(password, str):
        return wrong

    if cache.get(_failures_key(email), 0) >= MAX_FAILURES:
        return error("Too many attempts. Try again in a few minutes.", 429, "locked_out")
    user = authenticate(request, username=email, password=password)
    if user is None:
        cache.add(_failures_key(email), 0, LOCKOUT_SECONDS)
        try:
            cache.incr(_failures_key(email))
        except ValueError:  # expired between the add and the incr
            cache.set(_failures_key(email), 1, LOCKOUT_SECONDS)
        return wrong
    cache.delete(_failures_key(email))
    return JsonResponse({"token": tokens.issue(user), "user": user_json(user)})


@csrf_exempt
@require_POST
@tokens.token_required
def logout(request: HttpRequest) -> HttpResponse:
    request.auth_token.delete()
    return HttpResponse(status=204)


@require_GET
@tokens.token_required
def me(request: HttpRequest) -> HttpResponse:
    return JsonResponse({"user": user_json(request.user)})


@require_GET
@tokens.token_required
def export(request: HttpRequest) -> HttpResponse:
    """The account's data. Today that is the profile and the devices signed in: scores, hums and practice
    history are kept on the person's own device, not under their account."""
    user = request.user
    body = {
        "exported_at": timezone.now().isoformat(),
        "account": user_json(user),
        "signed_in_devices": [
            {"signed_in": row.created_at.isoformat()} for row in user.auth_tokens.order_by("created_at")
        ],
    }
    response = JsonResponse(body, json_dumps_params={"indent": 2})
    response["Content-Disposition"] = 'attachment; filename="hu-accompany-data.json"'
    return response


@csrf_exempt
@require_http_methods(["DELETE"])
@tokens.token_required
def delete_account(request: HttpRequest) -> HttpResponse:
    log.info("deleting account %s", request.user.pk)
    request.user.delete()  # takes the tokens with it
    return HttpResponse(status=204)
