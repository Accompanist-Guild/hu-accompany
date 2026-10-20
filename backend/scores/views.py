import re
import urllib.error
import urllib.request
from pathlib import Path

from django.conf import settings
from django.db.models import Q
from django.http import FileResponse, HttpRequest, HttpResponse, JsonResponse
from django.views.decorators.http import require_GET

from scores.models import Score

DEFAULT_LIMIT = 25
MAX_LIMIT = 50

MUSICXML_TYPE = "application/vnd.recordare.musicxml+xml"
# Where object storage is used, only paths shaped like the importer's output are ever requested.
_REMOTE_PATH = re.compile(r"^musicxml/[A-Za-z0-9._-]+\.musicxml$")
MAX_REMOTE_BYTES = 50 * 1024 * 1024
REMOTE_TIMEOUT_SECONDS = 10
# Cloudflare answers 403 to Python's default "Python-urllib/3.x" User-Agent on r2.dev addresses, so say who we are.
REMOTE_USER_AGENT = "hu-accompany-server/1.0"


@require_GET
def search_view(request: HttpRequest):
    """GET /api/scores/search?q=<text>&limit=<n> -- scores whose title or
    composer contains every word of `q`, best-rated first.

    Response: {"query": str, "results": [Score.as_summary(), ...]}
    400 if `q` is blank.
    """
    query = (request.GET.get("q") or "").strip()
    if not query:
        return JsonResponse({"error": "q is required"}, status=400)

    try:
        limit = int(request.GET.get("limit", DEFAULT_LIMIT))
    except ValueError:
        return JsonResponse({"error": "limit must be an integer"}, status=400)
    limit = max(1, min(limit, MAX_LIMIT))

    scores = Score.objects.all()
    for word in query.split():
        scores = scores.filter(Q(title__icontains=word) | Q(composer__icontains=word))

    return JsonResponse({
        "query": query,
        "results": [score.as_summary() for score in scores[:limit]],
    })


@require_GET
def musicxml_view(request: HttpRequest, score_id: int):
    """GET /api/scores/<id>/musicxml -- the score as uncompressed MusicXML.
    404 if the score or its file is missing."""
    score = Score.objects.filter(pk=score_id).first()
    if score is None:
        return JsonResponse({"error": f"score {score_id} not found"}, status=404)

    path = Path(settings.STORAGE_ROOT) / score.musicxml_path
    if path.is_file():
        return FileResponse(path.open("rb"), content_type=MUSICXML_TYPE)

    # A server with no persistent disk (Cloud Run) keeps the extracted files in object storage,
    # under the same path the importer recorded, and MUSICXML_BASE_URL says where.
    base_url = getattr(settings, "MUSICXML_BASE_URL", "")
    if base_url and _REMOTE_PATH.match(score.musicxml_path):
        return _from_object_storage(base_url, score.musicxml_path, score_id)

    return JsonResponse({"error": f"MusicXML for score {score_id} is missing"}, status=404)


def _from_object_storage(base_url: str, key: str, score_id: int):
    unavailable = JsonResponse(
        {"error": "The score storage is not available right now.", "code": "storage_unavailable"}, status=502
    )
    if not base_url.lower().startswith(("http://", "https://")):
        return unavailable  # misconfigured: never fetch file:// and the like
    url = f"{base_url.rstrip('/')}/{key}"
    try:
        request = urllib.request.Request(url, headers={"User-Agent": REMOTE_USER_AGENT})
        with urllib.request.urlopen(request, timeout=REMOTE_TIMEOUT_SECONDS) as remote:
            data = remote.read(MAX_REMOTE_BYTES + 1)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return JsonResponse({"error": f"MusicXML for score {score_id} is missing"}, status=404)
        return unavailable
    except (urllib.error.URLError, OSError):
        return unavailable
    if len(data) > MAX_REMOTE_BYTES:
        return unavailable
    return HttpResponse(data, content_type=MUSICXML_TYPE)
