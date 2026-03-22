#!/usr/bin/env bats

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$CALLER_PWD/notes"
}

@test "graph generates graph.md" {
  notes new -- --slug alpha --title "Alpha" --tags "test"

  run notes graph
  [ "$status" -eq 0 ]
  [ -f "$CALLER_PWD/notes/graph.md" ]
}

@test "graph detects outgoing wikilinks" {
  notes new -- --slug note-a --title "Note A" --tags "test" --body "This links to [[note-b]]."
  notes new -- --slug note-b --title "Note B" --tags "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "note-a.*note-b" "$CALLER_PWD/notes/graph.md"
}

@test "graph detects backlinks" {
  notes new -- --slug note-a --title "Note A" --tags "test" --body "This links to [[note-b]]."
  notes new -- --slug note-b --title "Note B" --tags "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "Backlinks" "$CALLER_PWD/notes/graph.md"
  grep -q "note-b.*note-a" "$CALLER_PWD/notes/graph.md"
}

@test "graph detects explicit relations" {
  notes new -- --slug note-x --title "Note X" --tags "test" --related "note-y"
  notes new -- --slug note-y --title "Note Y" --tags "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "Explicit Relations" "$CALLER_PWD/notes/graph.md"
  grep -q "note-x.*note-y" "$CALLER_PWD/notes/graph.md"
}

@test "graph detects orphaned notes" {
  notes new -- --slug lonely --title "Lonely Note" --tags "test"

  run notes graph
  [ "$status" -eq 0 ]

  grep -q "Orphaned Notes" "$CALLER_PWD/notes/graph.md"
  grep -q "Lonely Note" "$CALLER_PWD/notes/graph.md"
}

@test "graph empty directory generates valid output" {
  run notes graph
  [ "$status" -eq 0 ]

  [ -f "$CALLER_PWD/notes/graph.md" ]
  grep -q "No outgoing links yet" "$CALLER_PWD/notes/graph.md"
}
