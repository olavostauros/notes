#!/usr/bin/env bats

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  export NOTES_DIR="$CALLER_PWD/notes"
  mkdir -p "$NOTES_DIR"
}

create_note() {
  local slug="$1" title="$2" tags="$3" updated="$4"
  cat > "$NOTES_DIR/$slug.md" <<EOF
---
title: $title
tags: [$tags]
related: []
created: 2026-03-14
updated: ${updated:-2026-03-14}
---

# $title
EOF
}

@test "index generates index.md from note with frontmatter" {
  create_note "test-note" "Test Note" "testing, example" "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/index.md" ]
  grep -q "Test Note" "$NOTES_DIR/index.md"
  grep -q "testing" "$NOTES_DIR/index.md"
  grep -q "example" "$NOTES_DIR/index.md"
}

@test "index lists notes without frontmatter in unconverted section" {
  echo "# Just a plain note" > "$NOTES_DIR/no-frontmatter.md"

  run notes index
  [ "$status" -eq 0 ]

  grep -q "no-frontmatter.md" "$NOTES_DIR/index.md"
  grep -q "Without Frontmatter" "$NOTES_DIR/index.md"
}

@test "index empty directory generates valid output" {
  run notes index
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/index.md" ]
  grep -q "No tags yet" "$NOTES_DIR/index.md"
}

@test "index does not include index.md or graph.md as notes" {
  echo "# Old Index" > "$NOTES_DIR/index.md"
  echo "# Old Graph" > "$NOTES_DIR/graph.md"
  create_note "real-note" "Real Note" "test" "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  # index.md should be regenerated with Real Note
  grep -q "Real Note" "$NOTES_DIR/index.md"
  ! grep -q "Old Index" "$NOTES_DIR/index.md"
}

@test "index builds tag cloud with counts" {
  create_note "a" "Note A" "guide" "2026-03-14"
  create_note "b" "Note B" "guide, reference" "2026-03-14"
  create_note "c" "Note C" "reference" "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  # guide should have count 2, reference should have count 2
  grep -q '`guide` (2)' "$NOTES_DIR/index.md"
  grep -q '`reference` (2)' "$NOTES_DIR/index.md"
}

@test "index generates all-notes table" {
  create_note "alpha" "Alpha" "test" "2026-03-10"
  create_note "beta" "Beta" "test" "2026-03-15"

  run notes index
  [ "$status" -eq 0 ]

  grep -q "| Note | Tags | Updated |" "$NOTES_DIR/index.md"
  grep -q "Alpha" "$NOTES_DIR/index.md"
  grep -q "Beta" "$NOTES_DIR/index.md"
}
