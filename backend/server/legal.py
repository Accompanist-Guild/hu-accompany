"""The public pages App Store review looks for: /privacy, /terms and /support.

The text lives in backend/legal/*.html as plain HTML with {{PLACEHOLDERS}}, filled in from settings on each
request so the pages can't disagree with how the server is set up (who publishes it, where to write, how long
hum recordings are kept). They need no key: anyone, including App Review, must be able to read them.

When you change what privacy.html or terms.html say, change EFFECTIVE_DATE too.
"""

import html
import re
from functools import lru_cache

from django.conf import settings
from django.http import Http404, HttpResponse
from django.views.decorators.http import require_safe

APP_NAME = "Hu Accomponist"
EFFECTIVE_DATE = "October 15, 2026"

TITLES = {"privacy": "Privacy Policy", "terms": "Terms of Service", "support": "Support"}

# Only our own stylesheet (inline) may apply, nothing may run, and the page may not be framed.
CONTENT_SECURITY_POLICY = (
    "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
)

_TOKEN = re.compile(r"\{\{([A-Z_]+)\}\}")


@lru_cache(maxsize=16)
def _read(name: str) -> str:
    return (settings.BASE_DIR / "legal" / f"{name}.html").read_text(encoding="utf-8")


def _hours(value: float) -> str:
    """3.0 -> '3 hours', 1.0 -> '1 hour', 1.5 -> '1.5 hours'."""
    return f"{value:g} hour" + ("" if value == 1 else "s")


def render(page: str) -> str:
    """The finished HTML of one page. Raises KeyError for an unknown page or placeholder."""
    title = TITLES[page]
    values = {
        "TITLE": title,
        "APP_NAME": APP_NAME,
        "EFFECTIVE_DATE": EFFECTIVE_DATE,
        "PUBLISHER": getattr(settings, "LEGAL_PUBLISHER", "AG"),
        "SUPPORT_EMAIL": getattr(settings, "SUPPORT_EMAIL", ""),
        "HUM_RETENTION": _hours(float(getattr(settings, "HUM_TTL_HOURS", 3.0))),
    }
    # One pass over the whole page, so a value that happens to contain "{{...}}" is never expanded again.
    combined = _read("layout").replace("{{CONTENT}}", _read(page))
    return _TOKEN.sub(lambda m: html.escape(str(values[m.group(1)]), quote=True), combined)


def page_view(page: str):
    @require_safe
    def view(request, *args, **kwargs):
        if page not in TITLES:
            raise Http404
        response = HttpResponse(render(page), content_type="text/html; charset=utf-8")
        response["Content-Security-Policy"] = CONTENT_SECURITY_POLICY
        response["X-Content-Type-Options"] = "nosniff"
        response["Referrer-Policy"] = "no-referrer"
        response["Cache-Control"] = "public, max-age=300"
        return response

    view.__name__ = f"{page}_page"
    return view
