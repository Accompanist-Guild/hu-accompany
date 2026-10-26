"""Who may author guidelines: admins (is_staff) and verified contributors
(members of the `guideline_contributor` group). Everyone else can only read
published, public guidelines.

Verify a contributor with:
    python manage.py guideline_contributor add someone@example.com
"""

from functools import wraps

from django.http import JsonResponse

from User_accounts.tokens import token_required

CONTRIBUTOR_GROUP = "guideline_contributor"


def is_admin(user) -> bool:
    return bool(user and user.is_authenticated and user.is_active and user.is_staff)


def is_contributor(user) -> bool:
    return bool(
        user and user.is_authenticated and user.is_active and user.groups.filter(name=CONTRIBUTOR_GROUP).exists()
    )


def can_author(user) -> bool:
    return is_admin(user) or is_contributor(user)


def roles_of(user) -> list:
    roles = []
    if is_admin(user):
        roles.append("admin")
    if is_contributor(user):
        roles.append("contributor")
    return roles


def can_edit(user, guideline) -> bool:
    """Admins edit anything; contributors only what they own."""
    if is_admin(user):
        return True
    return is_contributor(user) and guideline.owner_id == user.pk


def author_required(view):
    """token_required, then 403 unless the user may author guidelines."""

    @token_required
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        if not can_author(request.user):
            return JsonResponse(
                {"error": "Only admins and verified contributors can edit guidelines.", "code": "forbidden"},
                status=403,
            )
        return view(request, *args, **kwargs)

    return wrapped
