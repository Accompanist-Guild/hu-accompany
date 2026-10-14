"""Issuing and checking the bearer tokens the app signs in with."""

import hashlib
import secrets
from functools import wraps

from django.http import HttpRequest, JsonResponse

from .models import AuthToken


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def issue(user) -> str:
    """A new token for `user`. This is the only time the token itself exists on the server."""
    token = secrets.token_urlsafe(32)
    AuthToken.objects.create(key_hash=_hash(token), user=user)
    return token


def presented(request: HttpRequest) -> str | None:
    header = request.headers.get("Authorization", "")
    scheme, _, token = header.partition(" ")
    return token.strip() if scheme.lower() == "bearer" and token.strip() else None


def token_required(view):
    """Runs `view(request, ...)` with `request.user` and `request.auth_token` set, or answers 401."""

    @wraps(view)
    def wrapped(request: HttpRequest, *args, **kwargs):
        token = presented(request)
        row = AuthToken.objects.select_related("user").filter(key_hash=_hash(token)).first() if token else None
        if row is None or not row.user.is_active:
            return JsonResponse({"error": "Please sign in again.", "code": "unauthorized"}, status=401)
        request.user = row.user
        request.auth_token = row
        return view(request, *args, **kwargs)

    return wrapped
