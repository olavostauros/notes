#!/usr/bin/env bats

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$NOTES_CALLER_PWD/notes"
}

@test "show prints a note by slug" {
  notes new --slug alpha --title "Alpha Note" --tags "testing" --body "Useful body text"

  run notes show alpha
  [ "$status" -eq 0 ]
  [[ "$output" == *"title: Alpha Note"* ]]
  [[ "$output" == *"Useful body text"* ]]
}

@test "show accepts an explicit note path" {
  notes new --slug alpha --title "Alpha Note" --tags "testing" --body "Useful body text"

  run notes show notes/alpha.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"# Alpha Note"* ]]
}

@test "show --json includes metadata and body" {
  notes new --slug beta --title "Beta Note" --tags "guide, testing" --body "JSON body text"

  run notes show beta --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; data = json.load(sys.stdin); assert data['title'] == 'Beta Note'; assert data['metadata']['tags'] == ['guide', 'testing']; assert 'JSON body text' in data['body']"
}

@test "show resolves exact title" {
  notes new --slug beta --title "Beta Note" --tags "guide" --body "Title lookup"

  run notes show "Beta Note"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Title lookup"* ]]
}

@test "show reports missing notes" {
  run notes show missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"note not found: missing"* ]]
}
