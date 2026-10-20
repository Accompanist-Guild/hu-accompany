"""Which PDMX scores the app may offer.

PDMX's "public domain" is a label the uploader chose on MuseScore, not a check: modern game and film music
sits in it marked public domain. A score is cleared only if the dataset flags no license conflict AND either
it is the uploader's own composition under an explicit CC0 dedication, or its composer is a historic composer
who died long enough ago that the work is free in every country we sell in. Anything else stays out.
"""

import csv
import json
import tempfile
from io import StringIO
from pathlib import Path

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase

from scores import clearance
from scores.clearance import PUBLIC_DOMAIN_DEATH_YEAR, assess, normalize_name


def row(**overrides):
    base = {
        "mxl": "./mxl/0/1/a.mxl",
        "title": "A piece",
        "composer_name": "Frédéric Chopin",
        "license": "publicdomain",
        "license_conflict": "False",
        "is_original": "False",
        "rating": "4.8",
        "subset:deduplicated": "True",
    }
    base.update(overrides)
    return base


class NormalizeTests(SimpleTestCase):
    def test_makes_the_many_spellings_of_a_name_comparable(self):
        for spelling in ("Frédéric Chopin", "FRÉDÉRIC  CHOPIN", "frederic chopin", "Frederic Chopin."):
            self.assertEqual(normalize_name(spelling), "frederic chopin")

    def test_drops_years_prefixes_and_trailing_dots(self):
        self.assertEqual(normalize_name("W. A. Mozart (1756-1791)"), "w a mozart")
        self.assertEqual(normalize_name("Richard Wagner."), "richard wagner")
        self.assertEqual(normalize_name("Composed by Franz Schubert"), "franz schubert")
        self.assertEqual(normalize_name("Composer: Johannes Brahms"), "johannes brahms")
        self.assertEqual(normalize_name("Saint-Saëns"), "saint saens")

    def test_copes_with_empty_and_missing(self):
        self.assertEqual(normalize_name(None), "")
        self.assertEqual(normalize_name("  "), "")


class ComposerTableTests(SimpleTestCase):
    def test_nobody_in_the_table_died_after_the_cutoff(self):
        # The guard against adding a recent composer by mistake.
        too_recent = [c.surname for c in clearance.COMPOSERS if c.died > PUBLIC_DOMAIN_DEATH_YEAR]
        self.assertEqual(too_recent, [])

    def test_the_cutoff_is_conservative(self):
        # 1925: their music is free under life+70 anywhere, and published before 1931 so free in the US too.
        self.assertLessEqual(PUBLIC_DOMAIN_DEATH_YEAR, 1925)

    def test_death_years_of_famous_composers_are_right(self):
        known = {
            "Bach": 1750, "Handel": 1759, "Vivaldi": 1741, "Haydn": 1809, "Mozart": 1791, "Beethoven": 1827,
            "Schubert": 1828, "Chopin": 1849, "Schumann": 1856, "Liszt": 1886, "Wagner": 1883, "Verdi": 1901,
            "Brahms": 1897, "Tchaikovsky": 1893, "Dvorak": 1904, "Grieg": 1907, "Mahler": 1911, "Debussy": 1918,
            "Faure": 1924, "Puccini": 1924, "Satie": 1925, "Bizet": 1875, "Paganini": 1840, "Joplin": 1917,
            "Mendelssohn": 1847,
        }
        by_surname = {}
        for c in clearance.COMPOSERS:
            by_surname.setdefault(normalize_name(c.surname), []).append(c.died)
        for surname, died in known.items():
            self.assertIn(died, by_surname.get(normalize_name(surname), []), surname)

    def test_it_is_a_substantial_list(self):
        self.assertGreaterEqual(len(clearance.COMPOSERS), 150)

    def test_no_name_belongs_to_two_composers(self):
        # Built once at import, which raises on a clash; this keeps that honest.
        self.assertGreater(len(clearance.ALIASES), len(clearance.COMPOSERS))


class AssessTests(SimpleTestCase):
    def test_historic_composers_are_cleared_however_the_name_is_written(self):
        for name in (
            "Frédéric Chopin", "Frédérick Chopin", "Chopin", "Chopin, Frédéric", "Fryderyk Chopin",
            "J. S. Bach", "J.S. Bach", "JS Bach", "Johann Sebastian Bach", "Bach, Johann Sebastian", "C.P.E. Bach",
            "W. A. Mozart (1756-1791)", "Wolfgang Amadeus Mozart", "Mozart",
            "Richard Wagner.", "Georg Friedrich Händel", "George Frideric Handel",
            "Composed by Franz Schubert", "Ludwig van Beethoven", "Beethoven, Ludwig van",
            "Pyotr Ilyich Tchaikovsky", "Tchaikovsky", "Camille Saint-Saëns", "Saint-Saens",
            "Fanny (Mendelssohn) Hensel", "Claude Debussy", "Erik Satie", "Giacomo Puccini", "Johann Strauss",
            # as they really appear in the data
            "Joseph Küffner (1776 - 1856)", "Luigi Legnani(1790 - 1877)", "Turlough O'Carolan", "Edvard Grieg Op. 40",
            "L. van Beethoven", "Erik Satie(18661925)", "C.Czerny Op. 740 Book 1", "Heinrich Wilhelm Ernst",
        ):
            verdict = assess(row(composer_name=name))
            self.assertTrue(verdict.cleared, f"{name!r} should be cleared: {verdict}")
            self.assertEqual(verdict.reason, "historic composer")

    def test_modern_and_unknown_composers_are_not(self):
        for name in (
            "NA", "", "Composer", "composer", "Traditional", "Trad.", "anon.", "Unknown",
            "Toby Fox", "Koji Kondo", "Joe Hisaishi", "Composed by Toby Fox Arranged by Gonzalo Matus",
            "Whindersson Nunes", "Alexander Alexandrov", "Béla Bartók", "Maurice Ravel", "Sergei Rachmaninoff",
            "Richard Strauss", "Strauss", "George Gershwin", "Dmitri Shostakovich",
        ):
            verdict = assess(row(composer_name=name))
            self.assertFalse(verdict.cleared, f"{name!r} must not be cleared")

    def test_look_alikes_of_historic_names_are_not_cleared(self):
        # A bare "Bach" is refused too: living composers share it (Jan Bach, b. 1937), and the real Bach
        # entries in the data are almost all spelled out ("J. S. Bach"). Same for "Wagner" and "Strauss".
        for name in ("Bach", "Wagner", "P.D.Q. Bach", "PDQ Bach", "Bach (arr. Jacques Loussier)", "Mozart/Smith",
                     "Chopin x Hisaishi", "Johann Sebastian Bach Jr", "Wolfgang Mozart Jr"):
            self.assertFalse(assess(row(composer_name=name)).cleared, name)

    def test_a_license_conflict_rejects_even_bach(self):
        verdict = assess(row(composer_name="J. S. Bach", license_conflict="True"))
        self.assertFalse(verdict.cleared)
        self.assertEqual(verdict.reason, "license conflict")

    def test_only_the_two_dedication_labels_are_accepted(self):
        for label in ("publicdomain", "cc-zero"):
            self.assertTrue(assess(row(license=label)).cleared, label)
        for label in ("", None, "copyright", "cc-by", "cc-by-nc", "all-rights-reserved"):
            verdict = assess(row(license=label))
            self.assertFalse(verdict.cleared, label)
            self.assertEqual(verdict.reason, "license not accepted", label)

    def test_a_self_declared_original_is_not_trusted(self):
        # An audit of the real data found covers marked "original" and CC0 by their uploaders: Billie Eilish,
        # Coldplay, Disney, The Police, a Guardians of the Galaxy song... The flag is the uploader's word, so it
        # clears nothing.
        for composer, title in (
            ("billie eilish", "Bad Guy-23feb2020"),
            ("NA", "Coldplay - Orphans"),
            ("NA", "Into The Unknown (Frozen 2 )"),
            ("The Police", "Spirits in the Material World"),
            ("Arrgt : S. Hermand", "Come and Get your Love Les gardiens de la Galaxie"),
            ("Hinci", "Anything"),
        ):
            verdict = assess(row(composer_name=composer, title=title, is_original="True", license="cc-zero"))
            self.assertFalse(verdict.cleared, f"{composer!r} {title!r} must not be cleared")
            self.assertEqual(verdict.reason, "composer not recognised")

    def test_a_historic_composer_is_cleared_whatever_the_original_flag_says(self):
        self.assertTrue(assess(row(composer_name="Mozart", is_original="True")).cleared)
        self.assertTrue(assess(row(composer_name="Mozart", is_original="False")).cleared)

    def test_every_verdict_has_a_stable_reason_to_report(self):
        reasons = {assess(row(**o)).reason for o in (
            {}, {"composer_name": "NA"}, {"license_conflict": "True"}, {"license": "cc-by"},
        )}
        self.assertEqual(reasons, {
            "historic composer", "composer not recognised", "license conflict", "license not accepted",
        })


class LoadClearedTests(SimpleTestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "cleared.txt"

    def test_reads_paths_ignoring_comments_blanks_and_a_leading_dot_slash(self):
        self.path.write_text("# generated\n\nmxl/0/1/a.mxl\n./mxl/0/1/b.mxl\n  mxl/0/1/c.mxl  \n")
        self.assertEqual(clearance.load_cleared(self.path), frozenset({"mxl/0/1/a.mxl", "mxl/0/1/b.mxl", "mxl/0/1/c.mxl"}))

    def test_a_missing_list_is_an_error_that_says_how_to_make_it(self):
        with self.assertRaisesMessage(CommandError, "build_clearance"):
            clearance.load_cleared(Path(self.tmp.name) / "nope.txt")

    def test_an_empty_list_is_an_error_not_an_empty_library(self):
        self.path.write_text("# nothing\n")
        with self.assertRaisesMessage(CommandError, "empty"):
            clearance.load_cleared(self.path)


class BuildClearanceTests(SimpleTestCase):
    COLUMNS = ["mxl", "title", "composer_name", "license", "license_conflict", "is_original", "rating", "subset:deduplicated"]

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.rows = [
            row(mxl="./mxl/0/1/chopin.mxl", composer_name="Frédéric Chopin"),
            row(mxl="./mxl/0/1/bach.mxl", composer_name="J.S. Bach", license="cc-zero"),
            row(mxl="./mxl/0/1/conflict.mxl", composer_name="Beethoven", license_conflict="True"),
            row(mxl="./mxl/0/1/fox.mxl", composer_name="Toby Fox"),
            row(mxl="./mxl/0/1/fox2.mxl", composer_name="Toby Fox"),
            row(mxl="./mxl/0/1/na.mxl", composer_name="NA"),
            row(mxl="./mxl/0/1/own.mxl", composer_name="Hinci", is_original="True", license="cc-zero"),
            row(mxl="./mxl/0/1/dupe.mxl", composer_name="Mozart", **{"subset:deduplicated": "False"}),
        ]
        self.csv = self.root / "PDMX.csv"
        with open(self.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=self.COLUMNS)
            w.writeheader()
            w.writerows({k: r[k] for k in self.COLUMNS} for r in self.rows)

    def build(self):
        out = StringIO()
        call_command("build_clearance", pdmx_csv=self.csv, output_dir=self.root / "out", stdout=out)
        return out.getvalue()

    def test_writes_the_cleared_list_of_deduplicated_scores_only_sorted(self):
        self.build()
        lines = [l for l in (self.root / "out/cleared_mxl.txt").read_text().splitlines() if l and not l.startswith("#")]
        self.assertEqual(lines, ["mxl/0/1/bach.mxl", "mxl/0/1/chopin.mxl"])

    def test_the_report_counts_by_reason_and_lists_unrecognised_composers_for_review(self):
        self.build()
        report = json.loads((self.root / "out/clearance_report.json").read_text())
        self.assertEqual(report["scores_considered"], 7)  # the non-deduplicated one is not considered
        self.assertEqual(report["cleared"], 2)
        self.assertEqual(report["by_reason"]["historic composer"], 2)
        self.assertEqual(report["by_reason"]["license conflict"], 1)
        self.assertNotIn("own composition under CC0", report["by_reason"])
        self.assertEqual(report["by_reason"]["composer not recognised"], 4)  # Toby Fox x2, NA, and the self-declared "original"
        self.assertEqual(report["unrecognised_composers"][0], ["Toby Fox", 2])
        self.assertEqual(report["public_domain_death_year"], PUBLIC_DOMAIN_DEATH_YEAR)
        self.assertEqual(len(report["csv_sha256"]), 64)

    def test_the_build_is_repeatable(self):
        self.build()
        first = (self.root / "out/cleared_mxl.txt").read_text()
        self.build()
        self.assertEqual((self.root / "out/cleared_mxl.txt").read_text(), first)

    def test_it_says_what_it_did(self):
        out = self.build()
        self.assertIn("cleared: 2", out)

    def build_with_blocklist(self, lines):
        blocklist = self.root / "blocked.txt"
        blocklist.write_text(lines)
        out = StringIO()
        call_command("build_clearance", pdmx_csv=self.csv, output_dir=self.root / "out",
                     blocklist=blocklist, stdout=out)
        return json.loads((self.root / "out/clearance_report.json").read_text())

    def test_a_blocked_score_is_kept_out_even_though_the_rules_would_clear_it(self):
        # After a complaint about one score, it must stay gone when the list is rebuilt and re-imported.
        report = self.build_with_blocklist("# complaint 2026-11-02, rights-holder X\nmxl/0/1/chopin.mxl\n")
        lines = [l for l in (self.root / "out/cleared_mxl.txt").read_text().splitlines() if l and not l.startswith("#")]
        self.assertEqual(lines, ["mxl/0/1/bach.mxl"])
        self.assertEqual(report["by_reason"]["blocked after a complaint"], 1)
        self.assertEqual(report["by_reason"]["historic composer"], 1)

    def test_the_blocklist_may_use_the_dot_slash_form_and_blank_lines(self):
        self.build_with_blocklist("\n./mxl/0/1/bach.mxl\n\n")
        lines = [l for l in (self.root / "out/cleared_mxl.txt").read_text().splitlines() if l and not l.startswith("#")]
        self.assertEqual(lines, ["mxl/0/1/chopin.mxl"])

    def test_no_blocklist_file_means_nothing_is_blocked(self):
        self.assertEqual(clearance.load_blocked(self.root / "nope.txt"), frozenset())

    def test_a_csv_without_the_license_columns_is_refused(self):
        bad = self.root / "bad.csv"
        bad.write_text("mxl,title\nx,y\n")
        with self.assertRaisesMessage(CommandError, "license_conflict"):
            call_command("build_clearance", pdmx_csv=bad, output_dir=self.root / "o2", stdout=StringIO())

    def test_a_missing_csv_is_refused(self):
        with self.assertRaisesMessage(CommandError, "not found"):
            call_command("build_clearance", pdmx_csv=self.root / "nope.csv", output_dir=self.root / "o3", stdout=StringIO())
