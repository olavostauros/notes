"""Raw wikilink graph audit helpers."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

# Wikilinks anywhere in body text. [[target]] or [[target|display]].
# Targets and aliases stay on a single line (filenames can't contain newlines),
# so exclude \n to avoid pairing a stray "[[" with a much later "]]".
LINK_RE = re.compile(r"\[\[([^\]|\n]+)(?:\|[^\]\n]*)?\]\]")
FENCE_RE = re.compile(r"```.*?```", re.S)
INLINE_CODE_RE = re.compile(r"`[^`]*`")
FRONTMATTER_RE = re.compile(r"\A\ufeff?---\n.*?\n---\n", re.S)


@dataclass(frozen=True)
class NoteAudit:
    inbound: int
    outbound: int
    broken_targets: tuple[str, ...]


@dataclass(frozen=True)
class AuditResult:
    notes_dir: Path
    note_count: int
    notes: dict[str, NoteAudit]

    def to_json_dict(self) -> dict[str, dict[str, dict[str, int | list[str]]]]:
        return {
            "notes": {
                stem: {
                    "inbound": audit.inbound,
                    "outbound": audit.outbound,
                    "broken_targets": list(audit.broken_targets),
                }
                for stem, audit in sorted(self.notes.items())
            }
        }


def parse_top(value: str) -> int:
    try:
        top_n = int(value)
    except ValueError as exc:
        raise ValueError(f"--top must be an integer (got {value!r})") from exc
    if top_n < 1:
        raise ValueError(f"--top must be >= 1 (got {top_n})")
    return top_n


def is_external(target: str) -> bool:
    return "/" in target


def link_target_stem(target: str) -> str:
    return target.split("#", 1)[0].strip()


def scannable_body(text: str) -> str:
    body = FRONTMATTER_RE.sub("", text, count=1)
    return INLINE_CODE_RE.sub("", FENCE_RE.sub("", body))


def audit_directory(notes_dir: Path) -> AuditResult:
    notes = sorted(notes_dir.glob("*.md"))
    stems = {path.stem for path in notes}

    inbound: dict[str, int] = defaultdict(int)
    outbound: dict[str, int] = defaultdict(int)
    broken: dict[str, set[str]] = defaultdict(set)

    for path in notes:
        stem = path.stem
        text = path.read_text(encoding="utf-8", errors="replace")
        for raw_target in LINK_RE.findall(scannable_body(text)):
            target = link_target_stem(raw_target)
            if not target or is_external(target):
                continue
            outbound[stem] += 1
            if target in stems:
                inbound[target] += 1
            else:
                broken[stem].add(target)

    return AuditResult(
        notes_dir=notes_dir,
        note_count=len(notes),
        notes={
            stem: NoteAudit(
                inbound=inbound.get(stem, 0),
                outbound=outbound.get(stem, 0),
                broken_targets=tuple(sorted(broken.get(stem, set()))),
            )
            for stem in sorted(stems)
        },
    )


def fmt_top(counts: dict[str, int], n: int) -> list[tuple[str, int]]:
    rows = [(stem, count) for stem, count in counts.items() if count > 0]
    rows.sort(key=lambda item: (-item[1], item[0]))
    return rows[:n]


def render_human(result: AuditResult, top_n: int) -> str:
    inbound = {stem: audit.inbound for stem, audit in result.notes.items()}
    outbound = {stem: audit.outbound for stem, audit in result.notes.items()}
    lines: list[str] = [f"Scanned {result.note_count} note(s) under {result.notes_dir}.", ""]

    def render_top(label: str, counts: dict[str, int]) -> None:
        rows = fmt_top(counts, top_n)
        if not rows:
            lines.append(f"{label}: (no notes have any links yet)")
            lines.append("")
            return
        lines.append(f"{label}:")
        stem_width = max(len(stem) for stem, _ in rows)
        in_width = max(len(str(inbound[stem])) for stem, _ in rows)
        out_width = max(len(str(outbound[stem])) for stem, _ in rows)
        for stem, _ in rows:
            lines.append(
                f"  {stem.ljust(stem_width)}  "
                f"inbound: {inbound[stem]:>{in_width}}  "
                f"outbound: {outbound[stem]:>{out_width}}"
            )
        lines.append("")

    render_top(f"Top {top_n} by inbound links", inbound)
    render_top(f"Top {top_n} by outbound links", outbound)

    broken_pairs = sorted(
        (source, target)
        for source, audit in result.notes.items()
        for target in audit.broken_targets
    )
    if broken_pairs:
        lines.append(f"Broken wikilink targets ({len(broken_pairs)}):")
        source_width = max(len(source) for source, _ in broken_pairs)
        for source, target in broken_pairs:
            lines.append(f"  {source.ljust(source_width)}  → [[{target}]]")
    else:
        lines.append("Broken wikilink targets: none")
    return "\n".join(lines)


def render_json(result: AuditResult) -> str:
    return json.dumps(result.to_json_dict(), indent=2, sort_keys=True)
