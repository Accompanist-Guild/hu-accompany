"""Guidelines judge -- phase 2.

Rolls the per-phrase "guideline" findings (feedback_generator/guidelines/)
up into one line per authored rubric for the whole session: how many
phrases it was checked in, how many it failed, and the bars it failed most.

A rubric that passed every phrase leaves no phase-1 finding, so `rubrics`
lists only rubrics that failed somewhere; `guidelines` lists every
guideline that was checked (from each phrase's `guidelines_applied`) and
in how many phrases.
"""

from collections import Counter
from typing import Dict, List

from .. import Finding, JudgeResult, PieceContext

NAME = "guidelines"
PHASE = 2

CATEGORY = "guideline"
MAX_WORST_BARS = 5


def judge(ctx: PieceContext) -> JudgeResult:
    applied: Dict[int, dict] = {}
    for entry in ctx.phrases:
        for guideline in entry.get("guidelines_applied") or []:
            if isinstance(guideline, dict) and guideline.get("id") is not None:
                applied.setdefault(guideline["id"], guideline)

    rubrics: Dict[object, dict] = {}
    bar_counts: Dict[object, Counter] = {}
    for entry in ctx.phrases:
        for finding in entry.get("feedback") or []:
            if finding.get("category") != CATEGORY:
                continue
            details = finding.get("details") or {}
            key = details.get("rubric_id") if details.get("rubric_id") is not None else details.get("issue")
            row = rubrics.setdefault(
                key,
                {
                    "guideline_id": details.get("guideline_id"),
                    "guideline_title": details.get("guideline_title", ""),
                    "rubric_id": details.get("rubric_id"),
                    "label": details.get("label", ""),
                    "pass_rate": details.get("pass_rate"),
                    "phrases_failed": 0,
                    "measured_pass_rates": [],
                    "suggestion": details.get("suggestion", ""),
                    "severity": finding.get("severity", "minor"),
                    "message": finding.get("message", ""),
                },
            )
            row["phrases_failed"] += 1
            if details.get("measured_pass_rate") is not None:
                row["measured_pass_rates"].append(details["measured_pass_rate"])
            if finding.get("severity") == "major":
                row["severity"] = "major"
            bar_counts.setdefault(key, Counter()).update(details.get("failing_bars") or [finding.get("bars", 0)])

    phrases_checked = {
        guideline_id: sum(
            1
            for entry in ctx.phrases
            if any(isinstance(g, dict) and g.get("id") == guideline_id for g in entry.get("guidelines_applied") or [])
        )
        for guideline_id in applied
    }

    findings: List[Finding] = []
    summary_rows = []
    for key, row in rubrics.items():
        worst = [bar for bar, _ in sorted(bar_counts[key].items(), key=lambda kv: (-kv[1], kv[0]))][:MAX_WORST_BARS]
        rates = row.pop("measured_pass_rates")
        row["phrases_checked"] = max(phrases_checked.get(row["guideline_id"], 0), row["phrases_failed"])
        row["worst_bars"] = worst
        row["mean_failed_pass_rate"] = round(sum(rates) / len(rates), 3) if rates else None
        message = row.pop("message")
        severity = row.pop("severity")
        summary_rows.append(row)
        findings.append(
            Finding(
                bars=min(worst) if worst else 0,
                category=CATEGORY,
                severity=severity,
                confidence=1.0,
                message=message,
                details={"issue": f"rubric:{row['rubric_id']}", **row},
            )
        )

    findings.sort(key=lambda f: (-f.details["phrases_failed"], f.bars))
    return JudgeResult(
        category=NAME,
        score=None,
        findings=findings,
        details={
            "guidelines": [
                {**g, "phrases_checked": phrases_checked.get(g["id"], 0)} for g in applied.values()
            ],
            "rubrics": summary_rows,
        },
    )
