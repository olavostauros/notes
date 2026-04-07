#!/usr/bin/env bats

# Tests for the manifest merge driver (lib/manifest-merge-driver.sh).
# These test the driver script directly (not through git) for precise
# control over ancestor/ours/theirs inputs.

load test_helper

DRIVER="$MISE_CONFIG_ROOT/lib/manifest-merge-driver.sh"

# Helper: create a manifest file from lines
make_manifest() {
  local file="$1"
  shift
  : > "$file"
  for entry in "$@"; do
    echo -e "$entry" >> "$file"
  done
}

setup() {
  export TARGET_DIR="$BATS_TEST_TMPDIR/test-repo"
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init -q
  export CALLER_PWD="$TARGET_DIR"
  source "$MISE_CONFIG_ROOT/lib/common.sh"

  # Temp files for ancestor/ours/theirs
  ANCESTOR="$BATS_TEST_TMPDIR/ancestor"
  OURS="$BATS_TEST_TMPDIR/ours"
  THEIRS="$BATS_TEST_TMPDIR/theirs"
}

# ── Union merge (additions) ──────────────────────────────────

@test "merge driver: concurrent additions from both sides" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "ccc00001\tgamma.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  # Result is written to OURS
  result=$(cat "$OURS")
  [[ "$result" == *"alpha.md"* ]]
  [[ "$result" == *"beta.md"* ]]
  [[ "$result" == *"gamma.md"* ]]

  # Should be sorted by name (column 2)
  [ "$(head -1 "$OURS" | cut -f2)" = "alpha.md" ]
  [ "$(sed -n '2p' "$OURS" | cut -f2)" = "beta.md" ]
  [ "$(sed -n '3p' "$OURS" | cut -f2)" = "gamma.md" ]
}

@test "merge driver: identical additions on both sides" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "bbb00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 2 ]
  [[ "$(cat "$OURS")" == *"alpha.md"* ]]
  [[ "$(cat "$OURS")" == *"beta.md"* ]]
}

@test "merge driver: addition on one side only" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 2 ]
  [[ "$(cat "$OURS")" == *"beta.md"* ]]
}

# ── Deletions ─────────────────────────────────────────────────

@test "merge driver: deletion on one side is respected" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 1 ]
  [[ "$(cat "$OURS")" == *"alpha.md"* ]]
  [[ "$(cat "$OURS")" != *"beta.md"* ]]
}

@test "merge driver: deletion on both sides" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 1 ]
  [[ "$(cat "$OURS")" != *"beta.md"* ]]
}

@test "merge driver: deletion on one side + addition on the other" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "bbb00001\tbeta.md" "ccc00001\tgamma.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  # alpha kept, beta deleted by ours, gamma added by theirs
  [[ "$(cat "$OURS")" == *"alpha.md"* ]]
  [[ "$(cat "$OURS")" != *"beta.md"* ]]
  [[ "$(cat "$OURS")" == *"gamma.md"* ]]
}

# ── Conflicts ─────────────────────────────────────────────────

@test "merge driver: same name added independently prefers ours" {
  # Both sides add beta.md with different IDs, no ancestor entry.
  # This is the common case (two branches create the same note).
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "ccc00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  # Prefers ours ID
  grep -q "bbb00001" "$OURS"
  ! grep -q "ccc00001" "$OURS"
}

@test "merge driver: ancestor entry changed by both sides is a conflict" {
  # Ancestor has beta with one ID, both sides changed it differently.
  # This shouldn't happen in normal operation but is a true conflict.
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "ddd00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "eee00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 1 ]

  [[ "$(cat "$OURS")" == *"<<<<<<<"* ]]
  [[ "$(cat "$OURS")" == *"ddd00001"* ]]
  [[ "$(cat "$OURS")" == *"eee00001"* ]]
}

# ── Edge cases ────────────────────────────────────────────────

@test "merge driver: empty ancestor (both sides add from scratch)" {
  : > "$ANCESTOR"
  make_manifest "$OURS"   "aaa00001\talpha.md"
  make_manifest "$THEIRS" "bbb00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 2 ]
  [[ "$(cat "$OURS")" == *"alpha.md"* ]]
  [[ "$(cat "$OURS")" == *"beta.md"* ]]
}

@test "merge driver: no changes on either side" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 1 ]
}

@test "merge driver: result is sorted by name" {
  make_manifest "$ANCESTOR" ""
  make_manifest "$OURS"     "ccc00001\tzulu.md" "aaa00001\talpha.md"
  make_manifest "$THEIRS"   "bbb00001\tmiddle.md"

  # Ancestor is empty (fresh start)
  : > "$ANCESTOR"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  [ "$(sed -n '1p' "$OURS" | cut -f2)" = "alpha.md" ]
  [ "$(sed -n '2p' "$OURS" | cut -f2)" = "middle.md" ]
  [ "$(sed -n '3p' "$OURS" | cut -f2)" = "zulu.md" ]
}

# ── Filename safety ───────────────────────────────────────────

@test "merge driver: filenames with brackets are preserved" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tnotes [wip].md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  grep -qF "notes [wip].md" "$OURS"
  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 2 ]
}

@test "merge driver: filenames with spaces and punctuation are preserved" {
  make_manifest "$ANCESTOR" ""
  : > "$ANCESTOR"
  make_manifest "$OURS"   "aaa00001\tmy notes (draft).md" "bbb00001\tfile*.md"
  make_manifest "$THEIRS" "ccc00001\tother [v2].md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  grep -qF "my notes (draft).md" "$OURS"
  grep -qF "file*.md" "$OURS"
  grep -qF "other [v2].md" "$OURS"
  [ "$(wc -l < "$OURS" | tr -d ' ')" -eq 3 ]
}

@test "merge driver: theirs updates ID while ours unchanged — accepts theirs" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "ccc00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  # Theirs' new ID for beta is accepted
  grep -qF "ccc00001" "$OURS"
  ! grep -qF "bbb00001" "$OURS"
}

@test "merge driver: ours updates ID while theirs unchanged — accepts ours" {
  make_manifest "$ANCESTOR" "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "ddd00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "bbb00001\tbeta.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  grep -qF "ddd00001" "$OURS"
  ! grep -qF "bbb00001" "$OURS"
}
