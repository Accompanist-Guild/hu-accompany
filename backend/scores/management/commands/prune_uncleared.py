"""manage.py prune_uncleared -- remove imported scores that are not on the clearance list.

    python manage.py prune_uncleared            # only reports what it would remove
    python manage.py prune_uncleared --yes      # removes the rows and their local files
    python manage.py prune_uncleared --yes --keys-file removed_keys.txt

For a database filled before the clearance existed, or after the rules were tightened. Files already uploaded to a
bucket (Cloudflare R2) are not touched: --keys-file writes their names so they can be deleted there too.
"""

from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand

from scores import clearance
from scores.models import Score


class Command(BaseCommand):
    help = "Remove imported scores that are not cleared for copyright. Reports only unless --yes is given."

    def add_arguments(self, parser):
        parser.add_argument("--clearance", type=Path, default=clearance.DEFAULT_CLEARED_LIST)
        parser.add_argument("--yes", action="store_true", help="Actually remove them.")
        parser.add_argument("--keys-file", type=Path, help="Write the removed scores' bucket file names here.")

    def handle(self, *args, **opts):
        cleared = clearance.load_cleared(opts["clearance"])  # refuses (and removes nothing) without a list
        doomed = [s for s in Score.objects.all().order_by("pk") if s.pdmx_path.removeprefix("./") not in cleared]

        if not opts["yes"]:
            self.stdout.write(f"would remove: {len(doomed)} of {Score.objects.count()} scores (run again with --yes)")
            for score in doomed[:10]:
                self.stdout.write(f"  {score.composer!r}  {score.title!r}")
            return

        keys = [s.musicxml_path for s in doomed]
        for score in doomed:
            path = Path(settings.STORAGE_ROOT) / score.musicxml_path
            path.unlink(missing_ok=True)
            score.delete()
        if opts["keys_file"]:
            opts["keys_file"].write_text("".join(f"{k}\n" for k in keys), encoding="utf-8")
        self.stdout.write(f"removed: {len(doomed)}")
        if keys:
            self.stdout.write("Files already uploaded to a bucket are still there; delete those names too (see --keys-file).")
