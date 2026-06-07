from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))

import pytest
from audit import audit_directory, fmt_top, parse_top


def write_note(notes_dir: Path, stem: str, body: str) -> None:
    notes_dir.mkdir(parents=True, exist_ok=True)
    (notes_dir / f"{stem}.md").write_text(body, encoding="utf-8")


@pytest.fixture
def seed_notes(tmp_path: Path) -> Path:
    notes_dir = tmp_path / "notes"
    write_note(notes_dir, "alpha", "---\ntitle: Alpha\n---\nSee [[beta]] and [[gamma]].\n")
    write_note(notes_dir, "beta", "---\ntitle: Beta\n---\nRefers to [[alpha]] and [[gamma]].\n")
    write_note(notes_dir, "gamma", "---\ntitle: Gamma\n---\nRefers to [[alpha]] only.\n")
    write_note(notes_dir, "delta", "---\ntitle: Delta\n---\nNo links here.\n")
    write_note(
        notes_dir,
        "epsilon",
        "---\ntitle: Epsilon\n---\nHas [[alpha]], a broken [[doesnt-exist]], "
        "and an external [[KnickKnackLabs/repo]].\n",
    )
    return notes_dir


def test_audit_counts_seed_corpus(seed_notes: Path) -> None:
    result = audit_directory(seed_notes)

    assert result.note_count == 5
    assert set(result.notes) == {"alpha", "beta", "gamma", "delta", "epsilon"}
    assert result.notes["alpha"].inbound == 3
    assert result.notes["alpha"].outbound == 2
    assert result.notes["beta"].inbound == 1
    assert result.notes["beta"].outbound == 2
    assert result.notes["gamma"].inbound == 2
    assert result.notes["gamma"].outbound == 1
    assert result.notes["delta"].inbound == 0
    assert result.notes["delta"].outbound == 0
    assert result.notes["epsilon"].inbound == 0
    assert result.notes["epsilon"].outbound == 2
    assert result.notes["epsilon"].broken_targets == ("doesnt-exist",)


def test_top_sorting_excludes_zeroes(seed_notes: Path) -> None:
    result = audit_directory(seed_notes)
    inbound = {stem: audit.inbound for stem, audit in result.notes.items()}

    assert fmt_top(inbound, 2) == [("alpha", 3), ("gamma", 2)]


def test_ignores_code_fences_inline_code_and_frontmatter(tmp_path: Path) -> None:
    notes_dir = tmp_path / "notes"
    write_note(
        notes_dir,
        "source",
        '---\ntitle: Source\ndescription: "See [[frontmatter-only]]"\n---\n'
        "Inline code `[[inline-only]]`.\n\n"
        "```\n[[fence-only]]\n```\n\n"
        "Body has [[target]].\n",
    )
    write_note(notes_dir, "target", "---\ntitle: Target\n---\nBody.\n")

    result = audit_directory(notes_dir)

    assert result.notes["source"].outbound == 1
    assert result.notes["source"].broken_targets == ()
    assert result.notes["target"].inbound == 1


def test_aliases_anchors_empty_shapes_and_malformed_links(tmp_path: Path) -> None:
    notes_dir = tmp_path / "notes"
    write_note(
        notes_dir,
        "source",
        "Good alias: [[target|the target]].\n"
        "Good anchor: [[target#heading]].\n"
        "Empty target with alias: [[|alias-only]].\n"
        "Whitespace-only target: [[ ]].\n"
        "Unclosed: [[no-close\n"
        "Nested: [[a[b]c]]\n",
    )
    write_note(notes_dir, "target", "Body.\n")

    result = audit_directory(notes_dir)

    assert result.notes["source"].outbound == 2
    assert result.notes["source"].broken_targets == ()
    assert result.notes["target"].inbound == 2


def test_deduplicates_repeated_broken_target_per_source(tmp_path: Path) -> None:
    notes_dir = tmp_path / "notes"
    write_note(notes_dir, "dup", "First [[ghost]] then [[ghost]] then [[ghost]] again.\n")

    result = audit_directory(notes_dir)

    assert result.notes["dup"].outbound == 3
    assert result.notes["dup"].broken_targets == ("ghost",)


def test_bom_frontmatter_is_stripped(tmp_path: Path) -> None:
    notes_dir = tmp_path / "notes"
    write_note(
        notes_dir,
        "bom",
        '\ufeff---\ntitle: BOM\ndescription: "See [[frontmatter-only]]"\n---\nBody has [[real]] only.\n',
    )
    write_note(notes_dir, "real", "Body.\n")

    result = audit_directory(notes_dir)

    assert result.notes["bom"].outbound == 1
    assert result.notes["bom"].broken_targets == ()
    assert result.notes["real"].inbound == 1


@pytest.mark.parametrize("value", ["0", "-5"])
def test_parse_top_rejects_non_positive_values(value: str) -> None:
    with pytest.raises(ValueError, match="--top must be >= 1"):
        parse_top(value)


def test_parse_top_rejects_non_integer_values() -> None:
    with pytest.raises(ValueError, match="--top must be an integer"):
        parse_top("abc")
