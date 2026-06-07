#!/usr/bin/env bats

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$NOTES_CALLER_PWD/notes"
}

seed_corpus() {
  cat > "$NOTES_CALLER_PWD/notes/alpha.md" <<'EOF'
---
title: Alpha
---
See [[beta]] and [[gamma]].
EOF
  cat > "$NOTES_CALLER_PWD/notes/beta.md" <<'EOF'
---
title: Beta
---
Refers to [[alpha]] and [[gamma]].
EOF
  cat > "$NOTES_CALLER_PWD/notes/gamma.md" <<'EOF'
---
title: Gamma
---
Refers to [[alpha]] only.
EOF
  cat > "$NOTES_CALLER_PWD/notes/delta.md" <<'EOF'
---
title: Delta
---
No links here.
EOF
  cat > "$NOTES_CALLER_PWD/notes/epsilon.md" <<'EOF'
---
title: Epsilon
---
Has [[alpha]], a broken [[doesnt-exist]], and an external [[KnickKnackLabs/repo]].
EOF
}

@test "audit reports the human-readable summary through mise" {
  seed_corpus

  run notes audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scanned 5 note(s)"* ]]
  [[ "$output" == *"Top 10 by inbound links:"* ]]
  [[ "$output" == *"Top 10 by outbound links:"* ]]
  [[ "$output" == *"Broken wikilink targets (1):"* ]]
  [[ "$output" == *"epsilon"* ]]
  [[ "$output" == *"[[doesnt-exist]]"* ]]
  [[ "$output" != *"KnickKnackLabs/repo"* ]]
}

@test "audit --json emits the JSON payload through mise" {
  seed_corpus

  run notes audit --json
  [ "$status" -eq 0 ]
  [[ "$output" == "{"* ]]
  [[ "$output" == *'"notes"'* ]]
  [[ "$output" == *'"alpha"'* ]]
  [[ "$output" == *'"broken_targets"'* ]]
  [[ "$output" == *'"doesnt-exist"'* ]]
}

@test "audit --top changes the rendered section label" {
  seed_corpus

  run notes audit --top 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"Top 2 by inbound links:"* ]]
  [[ "$output" == *"Top 2 by outbound links:"* ]]
}

@test "audit rejects non-positive and non-integer --top values" {
  seed_corpus

  run notes audit --top 0
  [ "$status" -ne 0 ]
  [[ "$output" == *"--top must be >= 1"* ]]

  run notes audit --top -5
  [ "$status" -ne 0 ]
  [[ "$output" == *"--top must be >= 1"* ]]

  run notes audit --top abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"--top must be an integer"* ]]
}

@test "audit clears inherited usage_* values when flags are omitted" {
  seed_corpus
  export usage_dir="missing"
  export usage_top="1"
  export usage_json="true"

  run notes audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scanned 5 note(s)"* ]]
  [[ "$output" == *"Top 10 by inbound links:"* ]]
  [[ "$output" != "{"* ]]
}

@test "audit errors when notes directory is missing" {
  rm -rf "$NOTES_CALLER_PWD/notes"

  run notes audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes directory not found"* ]]
}

@test "audit handles empty notes directory cleanly" {
  run notes audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scanned 0 note(s)"* ]]
  [[ "$output" == *"no notes have any links yet"* ]]
  [[ "$output" == *"Broken wikilink targets: none"* ]]
}
