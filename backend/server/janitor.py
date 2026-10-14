"""Clears old hum files so a long-running instance doesn't fill its own memory.

On Cloud Run the container's disk is memory, and the hum feature keeps every upload, run
folder, transcription and rendered stem under HUM_DATA_DIR. Nothing in `hum/` deletes them,
and `hum/` is deliberately left alone, so this sweeps from the outside: files not touched for
HUM_TTL_HOURS (default 3) are removed. A session older than that finds its hum gone and the
app already says "Hum again" (hum/views.py: HUM_GONE).

Because it deletes things, it is strict about where it may act: never outside the folder it is
given (symlinks are not followed), never the folder itself, never a root like "/" or the home folder.
"""

import logging
import os
import stat
import threading
import time
from collections.abc import Mapping
from pathlib import Path

log = logging.getLogger(__name__)


def _check_root(root: Path) -> None:
    home = Path.home()
    if not root.is_absolute() or len(root.parts) < 3 or root == home or root in home.parents:
        raise ValueError(f"refusing to sweep {str(root)!r}: not a dedicated data folder")


def sweep(root: Path, max_age_seconds: float, now: float | None = None) -> int:
    """Deletes files under `root` last modified more than `max_age_seconds` ago, then folders
    left empty and also unchanged for that long (but not `root`). Returns how many files were deleted."""
    root = Path(root)
    _check_root(root)
    if not root.is_dir():
        return 0
    cutoff = (time.time() if now is None else now) - max_age_seconds
    removed = 0
    for directory, subdirs, files in os.walk(root, topdown=False, followlinks=False):
        for name in files:
            path = os.path.join(directory, name)
            try:
                info = os.lstat(path)
                if stat.S_ISREG(info.st_mode) and info.st_mtime < cutoff:
                    os.unlink(path)
                    removed += 1
            except OSError:
                pass  # vanished or busy: the next sweep will see it
        for name in subdirs:
            path = os.path.join(directory, name)
            try:
                info = os.lstat(path)
                # Only a folder that has sat unchanged past the cutoff, so one the engine has just
                # made and not yet written into is never pulled out from under it.
                if stat.S_ISDIR(info.st_mode) and info.st_mtime < cutoff:
                    os.rmdir(path)  # only succeeds when empty
            except OSError:
                pass
    return removed


def settings_from_env(env: Mapping[str, str]) -> tuple[Path, float, float]:
    """(folder, max age in seconds, seconds between sweeps)."""
    return (
        Path(env.get("HUM_DATA_DIR", "/tmp/hum_data")),
        float(env.get("HUM_TTL_HOURS", "3")) * 3600,
        float(env.get("HUM_SWEEP_MINUTES", "10")) * 60,
    )


def start_from_env(env: Mapping[str, str] = os.environ) -> threading.Thread:
    """Runs sweep() forever on a background thread. Called once, from the one gunicorn worker."""
    root, max_age, interval = settings_from_env(env)

    def loop():
        while True:
            try:
                removed = sweep(root, max_age)
                if removed:
                    log.info("janitor: removed %d old hum file(s) from %s", removed, root)
            except Exception:  # never let a bad sweep end the thread
                log.exception("janitor: sweep of %s failed", root)
            time.sleep(interval)

    thread = threading.Thread(target=loop, name="hum-janitor", daemon=True)
    thread.start()
    return thread
