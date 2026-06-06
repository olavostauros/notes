"""Small Markdown frontmatter helpers for notes tasks.

This intentionally avoids a YAML dependency. It supports the frontmatter shape
`notes new` writes plus simple block lists used by shared note repos.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
from typing import Any

LIST_KEYS = {"tags", "related"}


def parse_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def split_inline_list(value: str) -> list[str]:
    """Split a YAML-ish inline list without pulling in a YAML parser."""
    parts: list[str] = []
    current: list[str] = []
    quote: str | None = None
    escape = False

    for char in value:
        if escape:
            current.append(char)
            escape = False
            continue
        if char == "\\" and quote:
            current.append(char)
            escape = True
            continue
        if quote:
            current.append(char)
            if char == quote:
                quote = None
            continue
        if char in {'"', "'"}:
            quote = char
            current.append(char)
            continue
        if char == ",":
            item = parse_scalar("".join(current))
            if item:
                parts.append(item)
            current = []
            continue
        current.append(char)

    item = parse_scalar("".join(current))
    if item:
        parts.append(item)
    return parts


def parse_list(value: str) -> list[str]:
    value = value.strip()
    if not value:
        return []
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return split_inline_list(inner)
    return [parse_scalar(value)]


def parse_mapping_text(text: str, *, list_keys: set[str] = LIST_KEYS) -> dict[str, Any]:
    """Parse the small YAML-ish mapping subset notes uses.

    The parser is deliberately modest. It accepts scalar `key: value` pairs,
    inline lists for configured list keys, and indented block-list items for
    those same keys. It is not a general YAML parser.
    """
    data: dict[str, Any] = {}
    current_list_key: str | None = None
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if current_list_key and line.startswith((" ", "\t")) and stripped.startswith("-"):
            item = stripped[1:].strip()
            if item:
                data[current_list_key].append(parse_scalar(item))
            continue

        current_list_key = None
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if key in list_keys:
            data[key] = parse_list(value)
            if not value:
                current_list_key = key
        else:
            data[key] = parse_scalar(value)
    return data


def parse_frontmatter_text(text: str) -> tuple[dict[str, Any] | None, str]:
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end == -1:
        return None, text

    data = parse_mapping_text(text[4:end])

    body_start = end + len("\n---")
    if body_start < len(text) and text[body_start] == "\n":
        body_start += 1
    return data, text[body_start:]


def read_frontmatter(path: Path) -> tuple[dict[str, Any] | None, str | None]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None, None
    metadata, body = parse_frontmatter_text(text)
    return metadata, body



@dataclass(frozen=True)
class Note:
    path: Path
    metadata: dict[str, Any]
    body: str

    @property
    def slug(self) -> str:
        return self.path.stem

    @property
    def title(self) -> str:
        return str(self.metadata.get("title", "")).strip()

    @property
    def tags(self) -> list[str]:
        tags = self.metadata.get("tags", [])
        return tags if isinstance(tags, list) else []

    @property
    def date(self) -> str:
        return str(self.metadata.get("updated") or self.metadata.get("created") or "")

    @property
    def note_type(self) -> str:
        return str(self.metadata.get("type", ""))

    @property
    def status(self) -> str:
        return str(self.metadata.get("status", ""))

    def row(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "tags": self.tags,
            "date": self.date,
            "created": str(self.metadata.get("created", "")),
            "updated": str(self.metadata.get("updated", "")),
            "type": self.note_type,
            "status": self.status,
            "slug": self.slug,
            "path": str(self.path),
        }

    def json(self, include_body: bool = False) -> dict[str, Any]:
        row = self.row()
        row["metadata"] = self.metadata
        if include_body:
            row["body"] = self.body
        return row

    def searchable_blob(self) -> str:
        return "\n".join(
            [
                self.slug,
                self.title,
                json.dumps(self.metadata, ensure_ascii=False, sort_keys=True),
                self.body,
            ]
        )


def iter_notes(notes_dir: Path) -> list[Note]:
    notes: list[Note] = []
    for path in sorted(notes_dir.glob("*.md")):
        metadata, body = read_frontmatter(path)
        if metadata is None or body is None:
            continue
        note = Note(path=path, metadata=metadata, body=body)
        if not note.title:
            continue
        notes.append(note)
    return notes


def filter_notes(
    notes: list[Note],
    *,
    tag: str = "",
    note_type: str = "",
    status: str = "",
) -> list[Note]:
    filtered = notes
    if tag:
        filtered = [note for note in filtered if tag in note.tags]
    if note_type:
        filtered = [note for note in filtered if note.note_type == note_type]
    if status:
        filtered = [note for note in filtered if note.status == status]
    return filtered
