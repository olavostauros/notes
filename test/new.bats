#!/usr/bin/env bats

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$NOTES_CALLER_PWD/notes"
}

@test "new creates note with frontmatter" {
  run notes new -- --slug alpha --title "Alpha Note" --tags "testing"
  [ "$status" -eq 0 ]

  run notes list -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; d = json.load(sys.stdin); assert d[0]['title'] == 'Alpha Note'"
}

@test "new sets tags and dates" {
  notes new -- --slug beta --title "Beta" --tags "a, b" --created "2026-01-01" --updated "2026-03-20"

  run farts get tags "$NOTES_CALLER_PWD/notes/beta.md"
  [ "${lines[0]}" = "a" ]
  [ "${lines[1]}" = "b" ]

  run farts get created "$NOTES_CALLER_PWD/notes/beta.md"
  [ "$output" = "2026-01-01" ]

  run farts get updated "$NOTES_CALLER_PWD/notes/beta.md"
  [ "$output" = "2026-03-20" ]
}

@test "new appends body text" {
  notes new -- --slug with-body --title "Body Note" --body "Some content here."

  run farts body "$NOTES_CALLER_PWD/notes/with-body.md"
  [[ "$output" == *"Some content here."* ]]
}

@test "new fails if note already exists" {
  notes new -- --slug existing --title "First"

  run notes new -- --slug existing --title "Second"
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "new defaults dates to today" {
  notes new -- --slug today-note --title "Today"
  today=$(date +%Y-%m-%d)

  run farts get created "$NOTES_CALLER_PWD/notes/today-note.md"
  [ "$output" = "$today" ]
}
