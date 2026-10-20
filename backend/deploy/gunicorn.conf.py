"""Gunicorn settings for the container (Cloud Run). Used by the Dockerfile's CMD.

ONE worker process, several threads, on purpose. The hum feature keeps some state in the
process's memory (spoken replies, caches) and its files on this container's disk, so every
request must reach the same process. That is also why the Cloud Run service runs exactly one
instance (see deploy/README.md). More concurrency comes from threads, not workers.
"""

import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
workers = 1
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
# Rendering a song can take a while; Cloud Run's own request timeout is the real limit.
timeout = 300
graceful_timeout = 30
# Gunicorn's heartbeat file belongs in memory, not on a container disk that may be slow.
worker_tmp_dir = "/dev/shm"
accesslog = "-"
errorlog = "-"


def post_worker_init(worker):
    """Starts the sweep of old hum files in the one worker (see server/janitor.py)."""
    from server.janitor import start_from_env

    start_from_env()
