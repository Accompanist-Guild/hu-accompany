"""Which PDMX scores the app may offer, and why.

PDMX's "public domain" is a label the uploader picked on MuseScore. Nobody checks it, and modern game, film
and pop music sits in the dataset marked public domain. So the label is necessary but nowhere near enough.
A score is CLEARED only if all of these hold, and anything doubtful stays out:

1. the uploader's license is one of the two dedication labels (`publicdomain`, `cc-zero`);
2. the dataset authors flag no `license_conflict` (the score's own embedded license disagrees with the label);
3. its composer is in COMPOSERS below: a reviewed list of historic composers who died in or before
   PUBLIC_DOMAIN_DEATH_YEAR, so the music is free everywhere we sell the app.

There is deliberately NO route for "the uploader says it is their own composition" (`is_original`). An audit of the
real data found covers marked original and CC0 by their uploaders (Billie Eilish, Coldplay, Disney, The Police...);
a flag the uploader controls cannot clear anything.

The name must match a listed composer exactly (after tidying case, accents, punctuation, years and
"composed by"). "Bach (arr. Someone)", "P.D.Q. Bach", "Traditional", "NA" and every modern composer fail on purpose:
losing a legitimate score costs little, letting a copyrighted one through can cost a lot.

This is a screen, not legal advice or a guarantee. A recognised name can still be attached to the wrong piece, and
an uploader's own-composition claim cannot be checked. See docs/app-store/legal-and-shipping.md.
"""

import re
import unicodedata
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from django.core.management.base import CommandError

RULE_VERSION = 1

# A composer who died in or before this year: their music is free under "life + 70 years" in every country we
# sell in (death year + 70 is long past), and anything published in their lifetime was published before 1931,
# so it is free in the United States too. Later composers (Ravel d.1937, Rachmaninoff d.1943...) are free in
# some countries but not clearly in all, so they are left out. Raise it only after taking advice.
PUBLIC_DOMAIN_DEATH_YEAR = 1925

ACCEPTED_LICENSES = frozenset({"publicdomain", "cc-zero"})

CLEARANCE_DIR = Path(__file__).resolve().parent / "clearance"
DEFAULT_CLEARED_LIST = CLEARANCE_DIR / "cleared_mxl.txt"
# Scores removed after a complaint. They stay out whatever the rules say, so a rebuild cannot bring them back.
DEFAULT_BLOCKLIST = CLEARANCE_DIR / "blocked_mxl.txt"


@dataclass(frozen=True)
class Composer:
    given: str
    surname: str
    died: int
    aliases: tuple[str, ...] = ()
    # True when the surname by itself is safe to accept ("Chopin"). False when it is shared with living or
    # copyrighted people ("Strauss", "Wagner", "Bach"), so the full name is required.
    alone: bool = False


def _c(given: str, surname: str, died: int, *aliases: str, alone: bool = False) -> Composer:
    return Composer(given, surname, died, aliases, alone)


COMPOSERS: tuple[Composer, ...] = (
    # --- Medieval and Renaissance
    _c("Hildegard", "von Bingen", 1179, "Hildegard of Bingen"),
    _c("Guillaume de", "Machaut", 1377, alone=True),
    _c("Guillaume", "Dufay", 1474, "Guillaume du Fay", alone=True),
    _c("Johannes", "Ockeghem", 1497, alone=True),
    _c("Josquin", "des Prez", 1521, "Josquin Desprez", "Josquin des Pres", "Josquin"),
    _c("Thomas", "Tallis", 1585, alone=True),
    _c("Giovanni Pierluigi da", "Palestrina", 1594, "Giovanni da Palestrina", alone=True),
    _c("Orlande de", "Lassus", 1594, "Orlando di Lasso", "Roland de Lassus", "Orlando Lassus", alone=True),
    _c("William", "Byrd", 1623),
    _c("Tomas Luis de", "Victoria", 1611),
    _c("Carlo", "Gesualdo", 1613, alone=True),
    _c("John", "Dowland", 1626, alone=True),
    _c("Orlando", "Gibbons", 1625, alone=True),
    _c("Claudio", "Monteverdi", 1643, alone=True),
    _c("Girolamo", "Frescobaldi", 1643, alone=True),
    _c("Heinrich", "Schutz", 1672, alone=True),
    _c("Thomas", "Morley", 1602),
    _c("John", "Bull", 1628),
    _c("Giovanni", "Gabrieli", 1612, alone=True),
    _c("Michael", "Praetorius", 1621, alone=True),
    _c("Jan Pieterszoon", "Sweelinck", 1621, alone=True),
    _c("Jacques", "Arcadelt", 1568, alone=True),
    _c("Thoinot", "Arbeau", 1595, alone=True),
    # --- Baroque
    _c("Jean-Baptiste", "Lully", 1687, alone=True),
    _c("Henry", "Purcell", 1695, alone=True),
    _c("Marc-Antoine", "Charpentier", 1704, alone=True),
    _c("Johann", "Pachelbel", 1706, alone=True),
    _c("Dieterich", "Buxtehude", 1707, "Dietrich Buxtehude", alone=True),
    _c("Arcangelo", "Corelli", 1713, alone=True),
    _c("Alessandro", "Scarlatti", 1725),
    _c("Domenico", "Scarlatti", 1757, alone=True),
    _c("Tomaso", "Albinoni", 1751, "Tomaso Giovanni Albinoni", alone=True),
    _c("Francois", "Couperin", 1733, "Francois Couperin le Grand", alone=True),
    _c("Antonio", "Vivaldi", 1741, alone=True),
    _c("Georg Philipp", "Telemann", 1767, alone=True),
    _c("Jean-Philippe", "Rameau", 1764, alone=True),
    _c("George Frideric", "Handel", 1759, "Georg Friedrich Handel", "Georg Friedrich Haendel",
       "George Frederick Handel", "George Frederic Handel", alone=True),
    _c("Johann Sebastian", "Bach", 1750, "Johann S Bach"),
    _c("Carl Philipp Emanuel", "Bach", 1788),
    _c("Wilhelm Friedemann", "Bach", 1784),
    _c("Johann Christian", "Bach", 1782),
    _c("Johann Christoph Friedrich", "Bach", 1795),
    _c("Giovanni Battista", "Pergolesi", 1736, alone=True),
    _c("Benedetto", "Marcello", 1739),
    _c("Johann Jakob", "Froberger", 1667, alone=True),
    _c("Heinrich Ignaz Franz", "Biber", 1704, "Heinrich Biber", alone=True),
    _c("Johann", "Kuhnau", 1722, alone=True),
    _c("Jean-Marie", "Leclair", 1764, alone=True),
    _c("Louis-Claude", "Daquin", 1772, "Louis-Claude d'Aquin", alone=True),
    _c("Jan Dismas", "Zelenka", 1745, alone=True),
    _c("Johann Friedrich", "Fasch", 1758),
    _c("Francesco", "Geminiani", 1762, alone=True),
    _c("Pietro Antonio", "Locatelli", 1764, "Pietro Locatelli", alone=True),
    _c("Giuseppe", "Tartini", 1770, alone=True),
    _c("Jeremiah", "Clarke", 1707),
    _c("William", "Boyce", 1779),
    _c("Thomas", "Arne", 1778, "Thomas Augustine Arne"),
    _c("Johann Joachim", "Quantz", 1773, alone=True),
    _c("Elisabeth", "Jacquet de La Guerre", 1729, "Elisabeth-Claude Jacquet de La Guerre"),
    _c("Barbara", "Strozzi", 1677, alone=True),
    _c("Marin", "Marais", 1728, alone=True),
    _c("Michel-Richard", "de Lalande", 1726),
    _c("Francesco", "Cavalli", 1676, alone=True),
    _c("Giulio", "Caccini", 1618, alone=True),
    # --- Classical
    _c("Christoph Willibald", "Gluck", 1787, "Christoph Gluck"),
    _c("Joseph", "Haydn", 1809, "Franz Joseph Haydn", alone=True),
    _c("Michael", "Haydn", 1806),
    _c("Wolfgang Amadeus", "Mozart", 1791, alone=True),
    _c("Leopold", "Mozart", 1787),
    _c("Luigi", "Boccherini", 1805, alone=True),
    _c("Antonio", "Salieri", 1825, alone=True),
    _c("Muzio", "Clementi", 1832, alone=True),
    _c("Carl", "Ditters von Dittersdorf", 1799, "Karl Ditters von Dittersdorf", "Dittersdorf", alone=True),
    _c("Johann Baptist", "Vanhal", 1813, "Jan Krtitel Vanhal", alone=True),
    _c("Ignaz", "Pleyel", 1831, alone=True),
    _c("Leopold", "Kozeluch", 1818),
    _c("Johann Nepomuk", "Hummel", 1837, alone=True),
    _c("Ludwig van", "Beethoven", 1827, "L van Beethoven", alone=True),
    _c("Jan Ladislav", "Dussek", 1812, "Johann Ladislaus Dussek", alone=True),
    _c("Giovanni", "Paisiello", 1816, alone=True),
    _c("Domenico", "Cimarosa", 1801, alone=True),
    _c("Luigi", "Cherubini", 1842, alone=True),
    _c("Etienne-Nicolas", "Mehul", 1817),
    _c("Francois-Joseph", "Gossec", 1829),
    _c("Mauro", "Giuliani", 1829, alone=True),
    _c("Fernando", "Sor", 1839, "Fernando Sors"),
    _c("Dionisio", "Aguado", 1849, alone=True),
    _c("Ferdinando", "Carulli", 1841, alone=True),
    _c("Matteo", "Carcassi", 1853, alone=True),
    _c("Anton", "Diabelli", 1858, alone=True),
    _c("Carl", "Czerny", 1857, "Karl Czerny", "C Czerny", alone=True),
    _c("Friedrich", "Kuhlau", 1832, alone=True),
    _c("Johann Friedrich", "Burgmuller", 1874, "Friedrich Burgmuller", "Johann Friedrich Franz Burgmuller", alone=True),
    _c("Louis", "Spohr", 1859, "Ludwig Spohr", alone=True),
    _c("Carl Maria von", "Weber", 1826),
    _c("Rodolphe", "Kreutzer", 1831, alone=True),
    _c("Ferdinand", "Ries", 1838),
    _c("Bernhard", "Romberg", 1841),
    # --- Romantic
    _c("Franz", "Schubert", 1828, "Franz Peter Schubert", alone=True),
    _c("Gioachino", "Rossini", 1868, "Gioacchino Rossini", alone=True),
    _c("Vincenzo", "Bellini", 1835, alone=True),
    _c("Gaetano", "Donizetti", 1848, alone=True),
    _c("Niccolo", "Paganini", 1840, "Nicolo Paganini", alone=True),
    _c("Felix", "Mendelssohn", 1847, "Felix Mendelssohn Bartholdy", "Jakob Ludwig Felix Mendelssohn Bartholdy", alone=True),
    _c("Fanny", "Hensel", 1847, "Fanny Mendelssohn", "Fanny Mendelssohn Hensel", "Fanny Mendelssohn-Hensel"),
    _c("Robert", "Schumann", 1856, alone=True),
    _c("Clara", "Schumann", 1896, "Clara Wieck Schumann", "Clara Wieck"),
    _c("Frederic", "Chopin", 1849, "Fryderyk Chopin", "Frederick Chopin", "Frederic Francois Chopin",
       "Fryderyk Franciszek Chopin", "F Chopin", alone=True),
    _c("Franz", "Liszt", 1886, "Ferenc Liszt", "Franz von Liszt", alone=True),
    _c("Hector", "Berlioz", 1869, alone=True),
    _c("Giacomo", "Meyerbeer", 1864, alone=True),
    _c("Fromental", "Halevy", 1862, alone=True),
    _c("Adolphe", "Adam", 1856),
    _c("Daniel", "Auber", 1871, "Daniel-Francois-Esprit Auber", alone=True),
    _c("Otto", "Nicolai", 1849),
    _c("Albert", "Lortzing", 1851, alone=True),
    _c("Friedrich von", "Flotow", 1883, alone=True),
    _c("Jacques", "Offenbach", 1880, alone=True),
    _c("Charles", "Gounod", 1893, alone=True),
    _c("Georges", "Bizet", 1875, alone=True),
    _c("Camille", "Saint-Saens", 1921, alone=True),
    _c("Jules", "Massenet", 1912, alone=True),
    _c("Cesar", "Franck", 1890),
    _c("Leo", "Delibes", 1891, alone=True),
    _c("Edouard", "Lalo", 1892, alone=True),
    _c("Emmanuel", "Chabrier", 1894, alone=True),
    _c("Ernest", "Chausson", 1899, alone=True),
    _c("Gabriel", "Faure", 1924, alone=True),
    _c("Claude", "Debussy", 1918, "Claude-Achille Debussy", alone=True),
    _c("Erik", "Satie", 1925, "Eric Satie", alone=True),
    _c("Ambroise", "Thomas", 1896),
    _c("Charles-Valentin", "Alkan", 1888, alone=True),
    _c("Louis Moreau", "Gottschalk", 1869, alone=True),
    _c("Stephen", "Foster", 1864, "Stephen C Foster", "Stephen Collins Foster"),
    _c("Edvard", "Grieg", 1907, alone=True),
    _c("Niels", "Gade", 1890, "Niels W Gade", alone=True),
    _c("Bedrich", "Smetana", 1884, alone=True),
    _c("Antonin", "Dvorak", 1904, "Anton Dvorak", alone=True),
    _c("Zdenek", "Fibich", 1900, alone=True),
    _c("Johannes", "Brahms", 1897, alone=True),
    _c("Anton", "Bruckner", 1896, alone=True),
    _c("Gustav", "Mahler", 1911, alone=True),
    _c("Hugo", "Wolf", 1903),
    _c("Max", "Bruch", 1920, alone=True),
    _c("Max", "Reger", 1916, alone=True),
    _c("Engelbert", "Humperdinck", 1921, alone=True),
    _c("Richard", "Wagner", 1883, "Wilhelm Richard Wagner"),
    _c("Giuseppe", "Verdi", 1901, "Joseph Verdi", alone=True),
    _c("Giacomo", "Puccini", 1924, alone=True),
    _c("Ruggero", "Leoncavallo", 1919, alone=True),
    _c("Arrigo", "Boito", 1918, alone=True),
    _c("Amilcare", "Ponchielli", 1886, alone=True),
    _c("Pyotr Ilyich", "Tchaikovsky", 1893, "Peter Ilyich Tchaikovsky", "Piotr Ilyich Tchaikovsky", "Pyotr Tchaikovsky",
       "Peter Tchaikovsky", "Tschaikowsky", "Tchaikovski", "Pyotr Ilyich Tchaikovski", alone=True),
    _c("Modest", "Mussorgsky", 1881, "Modest Mussorgski", "Modeste Moussorgsky", "Moussorgsky", "Mussorgski", alone=True),
    _c("Nikolai", "Rimsky-Korsakov", 1908, "Nikolay Rimsky-Korsakov", alone=True),
    _c("Alexander", "Borodin", 1887, "Aleksandr Borodin", alone=True),
    _c("Mily", "Balakirev", 1910, alone=True),
    _c("Cesar", "Cui", 1918),
    _c("Mikhail", "Glinka", 1857, alone=True),
    _c("Anton", "Rubinstein", 1894),
    _c("Alexander", "Scriabin", 1915, "Alexander Skryabin", "Aleksandr Scriabin", "Alexandre Scriabin", alone=True),
    _c("Anatoly", "Lyadov", 1914, "Anatol Liadov", "Anatoly Liadov", alone=True),
    _c("Anton", "Arensky", 1906, alone=True),
    _c("Sergei", "Taneyev", 1915, alone=True),
    _c("Alexander", "Dargomyzhsky", 1869, alone=True),
    _c("Vasily", "Kalinnikov", 1901, alone=True),
    _c("Moritz", "Moszkowski", 1925, alone=True),
    _c("Isaac", "Albeniz", 1909, alone=True),
    _c("Enrique", "Granados", 1916, alone=True),
    _c("Pablo de", "Sarasate", 1908, alone=True),
    _c("Francisco", "Tarrega", 1909, alone=True),
    _c("Johann", "Strauss", 1899, "Johann Strauss II", "Johann Strauss Jr", "Johann Strauss the Younger",
       "Johann Strauss I", "Johann Strauss Sr", "Johann Strauss the Elder"),
    _c("Josef", "Strauss", 1870),
    _c("Eduard", "Strauss", 1916),
    _c("Franz von", "Suppe", 1895, alone=True),
    _c("Carl Michael", "Ziehrer", 1922, alone=True),
    _c("Emil", "Waldteufel", 1915, alone=True),
    _c("Joseph", "Lanner", 1843, "Josef Lanner", alone=True),
    _c("Hans Christian", "Lumbye", 1874, alone=True),
    _c("Arthur", "Sullivan", 1900, "Arthur Seymour Sullivan"),
    _c("Hubert", "Parry", 1918, "C Hubert H Parry"),
    _c("Charles Villiers", "Stanford", 1924),
    _c("Samuel", "Coleridge-Taylor", 1912),
    _c("Scott", "Joplin", 1917),
    _c("Edward", "MacDowell", 1908, alone=True),
    _c("Francesco Paolo", "Tosti", 1916, "Paolo Tosti", alone=True),
    _c("Eduardo", "di Capua", 1917),
    _c("Luigi", "Denza", 1922, alone=True),
    _c("Joseph", "Joachim", 1907),
    _c("Henri", "Vieuxtemps", 1881, alone=True),
    _c("Henryk", "Wieniawski", 1880, alone=True),
    _c("Charles", "de Beriot", 1870, alone=True),
    _c("Ferdinand", "David", 1873),
    _c("Ole", "Bull", 1880),
    _c("Johan", "Svendsen", 1911, "Johan Severin Svendsen", alone=True),
    _c("Franz", "Berwald", 1868, alone=True),
    _c("Felicien", "David", 1876),
    _c("Peter", "Cornelius", 1874),
    _c("Hans von", "Bulow", 1894),
    _c("Joachim", "Raff", 1882, alone=True),
    _c("Josef", "Rheinberger", 1901, alone=True),
    _c("Karl", "Goldmark", 1915, "Carl Goldmark"),
    _c("Robert", "Volkmann", 1883),
    _c("Carl", "Reinecke", 1910),
    _c("Felix", "Draeseke", 1913),
    _c("Carl", "Loewe", 1869),
    _c("Franz", "Lachner", 1890),
    _c("Heinrich", "Marschner", 1861, alone=True),
    _c("Conradin", "Kreutzer", 1849),
    _c("Giovanni", "Bottesini", 1889, alone=True),
    _c("Franz", "Doppler", 1883),
    _c("Ferenc", "Erkel", 1893, alone=True),
    _c("Alexandre", "Guilmant", 1911, "Felix Alexandre Guilmant", alone=True),
    _c("Giovanni", "Sgambati", 1914),
    _c("Giuseppe", "Martucci", 1909),
    _c("Ferruccio", "Busoni", 1924, alone=True),
    # --- Teaching repertoire and hymn tunes
    _c("Joseph", "Kuffner", 1856, alone=True),
    _c("Luigi", "Legnani", 1877, alone=True),
    _c("Turlough", "O'Carolan", 1738, "Turlough Carolan", "Carolan", alone=True),
    _c("Heinrich Wilhelm", "Ernst", 1865),
    _c("Henry", "Lemoine", 1854),
    _c("Francis", "Cutting", 1596),
    _c("Charles-Louis", "Hanon", 1900, alone=True),
    _c("Ferdinand", "Beyer", 1863),
    _c("Cornelius", "Gurlitt", 1901, alone=True),
    _c("Louis", "Kohler", 1886),
    _c("Stephen", "Heller", 1888),
    _c("Theodor", "Oesten", 1878),
    _c("Jean Louis", "Streabbog", 1886, "Louis Streabbog", alone=True),
    _c("Johann Baptist", "Cramer", 1858),
    _c("Henri", "Bertini", 1876, alone=True),
    _c("Theodor", "Kullak", 1882),
    _c("Adolf", "Henselt", 1889, alone=True),
    _c("Sigismond", "Thalberg", 1871, alone=True),
    _c("Ignaz", "Moscheles", 1870, alone=True),
    _c("William", "Mason", 1908),
    _c("Lowell", "Mason", 1872),
    _c("John Francis", "Wade", 1786),
    _c("Franz Xaver", "Gruber", 1863, "Franz Gruber"),
    _c("William H", "Monk", 1889, "William Henry Monk"),
    _c("John Bacchus", "Dykes", 1876, "John B Dykes"),
    _c("Jean", "Gobbaerts", 1886),
)


# ---- Name matching -------------------------------------------------------------------------------------------

_YEARS = re.compile(
    r"\(\s*(?:c\.?\s*)?\d{3,4}\s*[-–—]\s*\d{0,4}\s*\)"  # (1756-1791)
    r"|\(\s*\d{8}\s*\)"  # (18661925): the dash was lost in the upload
    r"|\b\d{3,4}\s*[-–—]\s*\d{3,4}\b"
)
_OPUS = re.compile(r"\bop\s*\d+.*$")  # "Edvard Grieg Op. 40"
_PREFIX = re.compile(r"^(?:composed by|composer|music by|by)\s+")


def normalize_name(raw) -> str:
    """Lower case, no accents, no punctuation, no life dates, no leading 'composed by'. '' for nothing."""
    text = unicodedata.normalize("NFKD", raw or "")
    text = "".join(ch for ch in text if not unicodedata.combining(ch)).lower()
    text = _YEARS.sub(" ", text)
    text = re.sub(r"[^a-z0-9 ]+", " ", text)
    text = _OPUS.sub("", " ".join(text.split())).strip()
    return _PREFIX.sub("", text)


def _aliases_of(composer: Composer) -> set[str]:
    given = normalize_name(composer.given).split()
    surname = normalize_name(composer.surname)
    names = {" ".join([*given, surname]), f"{surname} {' '.join(given)}".strip()}
    if len(given) >= 2:  # 'J. S. Bach' is safe; a single initial ('F. David', 'J. Strauss') is shared by several people
        initials = [word[0] for word in given]
        names |= {
            " ".join([*initials, surname]),  # j s bach
            "".join(initials) + " " + surname,  # js bach
            f"{surname} {' '.join(initials)}",  # bach j s
        }
    if composer.alone:
        names.add(surname)
    names |= {normalize_name(alias) for alias in composer.aliases}
    return {name for name in names if name}


def _build_aliases() -> dict[str, Composer]:
    table: dict[str, Composer] = {}
    for composer in COMPOSERS:
        for alias in _aliases_of(composer):
            other = table.get(alias)
            if other is not None and other != composer:
                raise ValueError(f"{alias!r} would belong to both {other} and {composer}")
            table[alias] = composer
    return table


ALIASES: dict[str, Composer] = _build_aliases()


# ---- The decision --------------------------------------------------------------------------------------------


@dataclass(frozen=True)
class Verdict:
    cleared: bool
    reason: str
    composer: str = ""


def _true(value) -> bool:
    return str(value).strip().lower() in ("true", "1")


def assess(row: Mapping[str, str]) -> Verdict:
    """Decides one PDMX.csv row. The reason is a short, stable phrase used in the report."""
    license_label = (row.get("license") or "").strip().lower()
    if license_label not in ACCEPTED_LICENSES:
        return Verdict(False, "license not accepted")
    if _true(row.get("license_conflict")):
        return Verdict(False, "license conflict")
    composer = ALIASES.get(normalize_name(row.get("composer_name")))
    if composer is not None:
        return Verdict(True, "historic composer", f"{composer.given} {composer.surname}")
    return Verdict(False, "composer not recognised")


def load_blocked(path: Path = DEFAULT_BLOCKLIST) -> frozenset[str]:
    """Score paths to keep out regardless of the rules. A missing file just means nothing is blocked."""
    path = Path(path)
    if not path.is_file():
        return frozenset()
    return frozenset(
        line.strip().removeprefix("./")
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )


# ---- The list the importer reads ------------------------------------------------------------------------------


def load_cleared(path: Path = DEFAULT_CLEARED_LIST) -> frozenset[str]:
    """The set of cleared score paths (like 'mxl/2/21/Qm....mxl'). Missing or empty is an error, never 'allow all'."""
    path = Path(path)
    if not path.is_file():
        raise CommandError(
            f"clearance list not found: {path}. Make it with: "
            "python manage.py build_clearance --pdmx-csv /path/to/PDMX.csv"
        )
    cleared = frozenset(
        line.strip().removeprefix("./")
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    )
    if not cleared:
        raise CommandError(f"clearance list {path} is empty; rebuild it with build_clearance")
    return cleared
