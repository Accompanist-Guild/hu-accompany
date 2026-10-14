# User_accounts: sign in, sign out, export and delete

Email-and-password accounts for the app, on Django's own `User` model. Mounted at `/api/auth/`
(see `urls.py`); the Flutter side is `frontend/lib/integrations/auth/`.

| Route | Does |
| --- | --- |
| `POST /api/auth/register` | `{email, password, name?}` → `201 {token, user}`. `409` if the email has an account. |
| `POST /api/auth/login` | `{email, password}` → `{token, user}`. `401` on a mismatch, `429` after 5 wrong passwords for an email (15 minutes). |
| `POST /api/auth/logout` | Signs out the device that sent the token. |
| `GET /api/auth/me` | The signed-in user; `401` once the token is no longer valid. |
| `GET /api/auth/export` | Everything held about the account, as JSON (what App Store and Play data requests ask for). |
| `DELETE /api/auth/account` | Deletes the account and every token (App Store and Play account-deletion rule). |

Everything but register and login takes `Authorization: Bearer <token>`.

- Tokens are random, long-lived (until logout or deletion) and stored only as a SHA-256 hash, so
  a leaked table can't be used to sign in (`tokens.py`).
- Scores, hums and practice history are not tied to accounts: they stay on the person's device, so
  the export holds the profile and the signed-in devices only. If hums or practice history are
  ever stored per account, add them to `views.export` and make sure `delete_account` removes them.
- The lockout counter uses Django's cache. The default per-process cache is enough for one server
  process; configure a shared cache if you run several.
- **Serve this over HTTPS before shipping.** The app finds the server over mDNS on the local
  network and talks plain HTTP, which is fine for development but would send passwords in the clear.

Tests: `python manage.py test User_accounts` (needs the Postgres from `settings.py`, or point
`DJANGO_SETTINGS_MODULE` at a settings module that uses SQLite).
