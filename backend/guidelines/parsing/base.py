from dataclasses import asdict, dataclass, field
from typing import List, Optional, Protocol, Tuple


@dataclass
class ParseResult:
    """What a translator understood from an author's rubric text.

    `rule` is the structured rubric (metric/operator/value/value_max/unit/
    applies_to) or None when the text couldn't be turned into one;
    `missing` names the parts it couldn't find; `matched_spans` are
    (start, end, role) character ranges of the text, for highlighting what
    was understood; `unrecognised` are leftover words it ignored.
    """

    rule: Optional[dict]
    matched_spans: List[Tuple[int, int, str]] = field(default_factory=list)
    unrecognised: List[str] = field(default_factory=list)
    missing: List[str] = field(default_factory=list)
    message: str = ""
    translator: str = ""

    def as_json(self) -> dict:
        data = asdict(self)
        data["matched_spans"] = [
            {"start": start, "end": end, "role": role} for start, end, role in self.matched_spans
        ]
        return data


class RubricTranslator(Protocol):
    """Turns free text into a structured rubric. The keyword translator is
    the only one today; an LLM-backed one can implement the same method."""

    name: str

    def parse(self, text: str) -> ParseResult: ...
