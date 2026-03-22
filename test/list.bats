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

@test "list shows notes with frontmatter" {
  create_note "alpha" "Alpha Note" "testing" "2026-03-14"

  run notes list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Alpha Note"* ]]
}

@test "list skips files without frontmatter" {
  create_note "real" "Real Note" "test" "2026-03-14"
  echo "# No frontmatter" > "$NOTES_DIR/plain.md"

  run notes list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Real Note"* ]]
  [[ "$output" != *"plain"* ]]
}

@test "list --json outputs valid JSON" {
  create_note "beta" "Beta Note" "guide, testing" "2026-03-15"

  run notes list -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; data = json.load(sys.stdin); assert len(data) == 1; assert data[0]['title'] == 'Beta Note'"
}

@test "list --json includes tags as array" {
  create_note "multi" "Multi Tag" "alpha, beta, gamma" "2026-03-15"

  run notes list -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; data = json.load(sys.stdin); assert data[0]['tags'] == ['alpha', 'beta', 'gamma']"
}

@test "list --recent limits output" {
  create_note "old" "Old Note" "test" "2026-03-10"
  create_note "mid" "Mid Note" "test" "2026-03-15"
  create_note "new" "New Note" "test" "2026-03-20"

  run notes list -- --json --recent 2
  [ "$status" -eq 0 ]
  count=$(echo "$output" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
  [ "$count" -eq 2 ]
}

@test "list --recent returns most recent first" {
  create_note "old" "Old Note" "test" "2026-03-10"
  create_note "new" "New Note" "test" "2026-03-20"

  run notes list -- --json --recent 1
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; assert json.load(sys.stdin)[0]['title'] == 'New Note'"
}

@test "list --tag filters by tag" {
  create_note "guide-a" "Guide A" "guide" "2026-03-14"
  create_note "ref-b" "Ref B" "reference" "2026-03-14"

  run notes list -- --json --tag guide
  [ "$status" -eq 0 ]
  count=$(echo "$output" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
  [ "$count" -eq 1 ]
  echo "$output" | python3 -c "import sys, json; assert json.load(sys.stdin)[0]['title'] == 'Guide A'"
}

@test "list empty directory shows no notes" {
  run notes list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No notes found"* ]]
}

@test "list --json empty directory returns empty array" {
  run notes list -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys, json; assert json.load(sys.stdin) == []"
}
