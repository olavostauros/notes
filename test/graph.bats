#!/usr/bin/env bats

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  export NOTES_DIR="$CALLER_PWD/notes"
  mkdir -p "$NOTES_DIR"
}

create_note() {
  local slug="$1" title="$2" tags="$3" related="$4" body="$5"
  cat > "$NOTES_DIR/$slug.md" <<EOF
---
title: $title
tags: [$tags]
related: [${related:-}]
created: 2026-03-14
updated: 2026-03-14
---

# $title

${body:-}
EOF
}

@test "graph generates graph.md" {
  create_note "alpha" "Alpha" "test"

  run notes graph
  [ "$status" -eq 0 ]
  [ -f "$NOTES_DIR/graph.md" ]
}

@test "graph detects outgoing wikilinks" {
  create_note "note-a" "Note A" "test" "" "This links to [[note-b]]."
  create_note "note-b" "Note B" "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "note-a.*note-b" "$NOTES_DIR/graph.md"
}

@test "graph detects backlinks" {
  create_note "note-a" "Note A" "test" "" "This links to [[note-b]]."
  create_note "note-b" "Note B" "test"

  run notes graph
  [ "$status" -eq 0 ]

  # note-b should have a backlink from note-a
  grep -q "Backlinks" "$NOTES_DIR/graph.md"
  grep -q "note-b.*note-a" "$NOTES_DIR/graph.md"
}

@test "graph detects explicit relations" {
  create_note "note-x" "Note X" "test" "note-y"
  create_note "note-y" "Note Y" "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "Explicit Relations" "$NOTES_DIR/graph.md"
  grep -q "note-x.*note-y" "$NOTES_DIR/graph.md"
}

@test "graph detects orphaned notes" {
  create_note "lonely" "Lonely Note" "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "Orphaned Notes" "$NOTES_DIR/graph.md"
  grep -q "Lonely Note" "$NOTES_DIR/graph.md"
}

@test "graph empty directory generates valid output" {
  run notes graph
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/graph.md" ]
  grep -q "No outgoing links yet" "$NOTES_DIR/graph.md"
}
