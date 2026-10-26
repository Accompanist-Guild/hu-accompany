"""Free text -> structured rubric.

get_translator() is the single place a translator is chosen. Only the
deterministic keyword translator exists today; an LLM translator can be
added behind the same RubricTranslator interface and selected here.
"""

from .base import ParseResult, RubricTranslator
from .keyword_parser import KeywordTranslator

_TRANSLATORS = {"keyword": KeywordTranslator}


def get_translator(name: str = "keyword") -> RubricTranslator:
    return _TRANSLATORS.get(name, KeywordTranslator)()


__all__ = ["ParseResult", "RubricTranslator", "KeywordTranslator", "get_translator"]
