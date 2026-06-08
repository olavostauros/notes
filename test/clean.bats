#!/usr/bin/env bats

load test_helper

# --- Orphans (text) ---

@test "clean --orphans reports no orphans when notes dir missing" {
  run notes clean --orphans
  [ "$status" -eq 0 ]
  [[ "$output" == *"No orphan files found"* ]]
}

@test "clean --orphans removes orphan file from disk" {
  mkdir -p "$TARGET_DIR/notes"
  touch "$TARGET_DIR/notes/graph.md"

  run notes clean --orphans
  [ "$status" -eq 0 ]
  [ ! -f "$TARGET_DIR/notes/graph.md" ]
  [[ "$output" == *"graph.md"* ]]
}

@test "clean --orphans removes multiple orphan files" {
  mkdir -p "$TARGET_DIR/notes"
  touch "$TARGET_DIR/notes/graph.md"
  touch "$TARGET_DIR/notes/index.md"

  run notes clean --orphans
  [ "$status" -eq 0 ]
  [ ! -f "$TARGET_DIR/notes/graph.md" ]
  [ ! -f "$TARGET_DIR/notes/index.md" ]
  [[ "$output" == *"2"* ]]
}

@test "clean --orphans ignores non-orphan notes" {
  mkdir -p "$TARGET_DIR/notes"
  echo "# Alpha" > "$TARGET_DIR/notes/alpha.md"
  touch "$TARGET_DIR/notes/graph.md"

  run notes clean --orphans
  [ "$status" -eq 0 ]
  [ ! -f "$TARGET_DIR/notes/graph.md" ]
  [ -f "$TARGET_DIR/notes/alpha.md" ]
}

@test "clean --orphans removes orphan and manifest entry when present in manifest" {
  mkdir -p "$TARGET_DIR/notes"
  printf 'aaaaaaaa\tgraph.md\n' > "$TARGET_DIR/notes/.manifest"
  touch "$TARGET_DIR/notes/graph.md"
  touch "$TARGET_DIR/notes/aaaaaaaa"

  run notes clean --orphans
  [ "$status" -eq 0 ]
  [[ "$output" == *"manifest entry"* ]]
  [ ! -f "$TARGET_DIR/notes/graph.md" ]
  [ ! -f "$TARGET_DIR/notes/aaaaaaaa" ]
  run grep -c 'aaaaaaaa' "$TARGET_DIR/notes/.manifest"
  [ "$status" -eq 1 ]
}

@test "clean --orphans is a no-op without --orphans flag" {
  mkdir -p "$TARGET_DIR/notes"
  touch "$TARGET_DIR/notes/graph.md"

  run notes clean
  [ "$status" -eq 0 ]
  [ -f "$TARGET_DIR/notes/graph.md" ]
  [[ "$output" == *"--orphans"* ]]
}

@test "clean --orphans shows count of removed files" {
  mkdir -p "$TARGET_DIR/notes"
  touch "$TARGET_DIR/notes/graph.md"

  run notes clean --orphans
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removed 1"* ]]
}