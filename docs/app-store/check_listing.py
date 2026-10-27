"""Checks the App Store listing in listing.md against Apple's length limits. Run: python3 docs/app-store/check_listing.py"""

import pathlib
import re
import sys

text = (pathlib.Path(__file__).parent / "listing.md").read_text(encoding="utf-8")


def section(title: str) -> str:
    match = re.search(rf"^## {re.escape(title)}[^\n]*\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    return match.group(1).strip()


def row(name: str) -> str:
    return re.search(rf"^\| {re.escape(name)}[^|]*\| (.*?) \|$", text, re.M).group(1)


checks = {
    "Name": (row("Name"), 30),
    "Subtitle": (row("Subtitle"), 30),
    "Promotional text": (section("Promotional text"), 170),
    "Description": (section("Description"), 4000),
    "Keywords": (section("Keywords"), 100),
}
failed = False
for name, (value, limit) in checks.items():
    ok = len(value) <= limit
    failed |= not ok
    print(f"{'ok ' if ok else 'TOO LONG'} {name}: {len(value)}/{limit}")
sys.exit(1 if failed else 0)
