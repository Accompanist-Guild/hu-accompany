from django.conf import settings
from django.db import models


class AuthToken(models.Model):
    """A signed-in device. Only the SHA-256 of the token is stored, so a leaked table can't be used to sign in.

    Deleting the user deletes their tokens, which is what signs every device out when an account is deleted.
    """

    key_hash = models.CharField(max_length=64, unique=True)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="auth_tokens")
    created_at = models.DateTimeField(auto_now_add=True)
