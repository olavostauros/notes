#!/usr/bin/env bats

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$CALLER_PWD/notes"
}

@test "index generates index.md from note with frontmatter" {
  notes new -- --slug test-note --title "Test Note" --tags "testing, example" --updated "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  [ -f "$CALLER_PWD/notes/index.md" ]
  grep -q "Test Note" "$CALLER_PWD/notes/index.md"
  grep -q "testing" "$CALLER_PWD/notes/index.md"
  grep -q "example" "$CALLER_PWD/notes/index.md"
}

@test "index lists notes without frontmatter in unconverted section" {
  echo "# Just a plain note" > "$CALLER_PWD/notes/no-frontmatter.md"

  run notes index
  [ "$status" -eq 0 ]

  grep -q "no-frontmatter.md" "$CALLER_PWD/notes/index.md"
  grep -q "Without Frontmatter" "$CALLER_PWD/notes/index.md"
}

@test "index empty directory generates valid output" {
  run notes index
  [ "$status" -eq 0 ]

  [ -f "$CALLER_PWD/notes/index.md" ]
  grep -q "No tags yet" "$CALLER_PWD/notes/index.md"
}

@test "index does not include index.md or graph.md as notes" {
  echo "# Old Index" > "$CALLER_PWD/notes/index.md"
  echo "# Old Graph" > "$CALLER_PWD/notes/graph.md"
  notes new -- --slug real-note --title "Real Note" --tags "test" --updated "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  grep -q "Real Note" "$CALLER_PWD/notes/index.md"
  ! grep -q "Old Index" "$CALLER_PWD/notes/index.md"
}

@test "index builds tag cloud with counts" {
  notes new -- --slug a --title "Note A" --tags "guide" --updated "2026-03-14"
  notes new -- --slug b --title "Note B" --tags "guide, reference" --updated "2026-03-14"
  notes new -- --slug c --title "Note C" --tags "reference" --updated "2026-03-14"

  run notes index
  [ "$status" -eq 0 ]

  grep -q '`guide` (2)' "$CALLER_PWD/notes/index.md"
  grep -q '`reference` (2)' "$CALLER_PWD/notes/index.md"
}

@test "index generates all-notes table" {
  notes new -- --slug alpha --title "Alpha" --tags "test" --updated "2026-03-10"
  notes new -- --slug beta --title "Beta" --tags "test" --updated "2026-03-15"

  run notes index
  [ "$status" -eq 0 ]

  grep -q "| Note | Tags | Updated |" "$CALLER_PWD/notes/index.md"
  grep -q "Alpha" "$CALLER_PWD/notes/index.md"
  grep -q "Beta" "$CALLER_PWD/notes/index.md"
}
