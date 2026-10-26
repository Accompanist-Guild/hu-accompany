"""The keyword vocabulary the rubric parser understands.

Everything an author can write is listed here, so teaching the parser a new
phrasing is a one-line change. Phrases are matched case-insensitively on
word boundaries; longer phrases win over shorter ones that overlap them.
"""

# Metric -> phrases that name it. Checked in this order: the first metric
# with any match wins, so the more specific metrics come first ("silent
# between notes" is a gap even though it also mentions notes).
METRIC_PHRASES = (
    ("note_gap", (
        "gap", "gaps", "space between", "spaces between", "silence between", "silent between",
        "separation", "separated by", "break between", "breaks between", "detached by",
    )),
    ("volume_range", (
        "dynamic range", "volume range", "range of volume", "dynamic contrast", "contrast",
        "louder", "softer", "loudness", "volume",
    )),
    ("onset_deviation", (
        "timing", "on time", "early", "late", "onset", "onsets", "attack", "attacks", "off the beat",
    )),
    ("sounding_ratio", (
        "held", "hold", "holds", "sustain", "sustained", "sounding", "sounded", "note length",
        "length", "duration", "last", "lasts",
    )),
)

# Comparator phrase -> operator. "between X and Y" is handled separately.
COMPARATORS = {
    "more than": "gt", "greater than": "gt", "longer than": "gt", "louder than": "gt", "bigger than": "gt",
    "larger than": "gt", "higher than": "gt", "over": "gt", "above": "gt", "exceeds": "gt", "exceed": "gt",
    ">": "gt",
    "at least": "gte", "no less than": "gte", "not less than": "gte", "minimum of": "gte", "min": "gte",
    ">=": "gte", "\u2265": "gte",
    "less than": "lt", "fewer than": "lt", "shorter than": "lt", "softer than": "lt", "smaller than": "lt",
    "lower than": "lt", "under": "lt", "below": "lt", "<": "lt",
    "at most": "lte", "no more than": "lte", "not more than": "lte", "within": "lte", "up to": "lte",
    "maximum of": "lte", "max": "lte", "<=": "lte", "\u2264": "lte",
}

# Common slips, rewritten before matching (same length, so spans still line up).
TYPOS = (
    (r"\b(more|less|greater|longer|shorter|louder|softer|fewer|bigger|larger|higher|lower|smaller) then\b",
     r"\1 than"),
)

# Unit phrases (after the number) -> unit. Order matters: relative units
# first, so "% of a beat" isn't read as a bare "%".
UNIT_PATTERNS = (
    (r"(?:%|percent|per cent)\s*(?:of\s+)?(?:a\s+|the\s+|one\s+)?beats?\b", "pct_of_beat"),
    (r"(?:%|percent|per cent)\s*(?:of\s+)?(?:the\s+|its\s+|a\s+)?(?:written\s+)?(?:note|notes|note's|length|duration|value)\b",
     "pct_of_note"),
    (r"(?:%|percent|per cent)", "pct"),  # resolved per metric below
    (r"(?:ms|msec|millisecond|milliseconds)\b", "ms"),
    (r"(?:s|sec|secs|second|seconds)\b", "sec"),
    (r"(?:db|decibel|decibels)\b", "db"),
    (r"(?:x|times)\s*(?:the\s+)?(?:written\s+)?(?:length|duration|value)?", "ratio"),
)

# A bare "%" means a percentage of the note for these metrics.
BARE_PERCENT = {"note_gap": "pct_of_note", "sounding_ratio": "pct_of_note"}

# Used when no unit is written at all (only where it can't be ambiguous).
DEFAULT_UNIT = {"volume_range": "volume", "sounding_ratio": "ratio"}

APPLIES_TO_PHRASES = (
    ("staccato", ("staccato",)),
    ("legato", ("legato", "slurred")),
    ("unmarked", ("unmarked", "unmarked notes")),
)

STOPWORDS = frozenset(
    "a an the of to in on at for by and or is are be been should must notes note between each every "
    "it its this that these those than then with played play playing written era".split()
)
