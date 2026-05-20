#!/usr/bin/env bats

# Tests for manifest helpers in lib/common.sh:
#   - manifest_id_for_name, manifest_has_id, manifest_name_for_id

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  source "$REPO_DIR/lib/common.sh"

  mkdir -p "$CALLER_PWD/notes"
  MANIFEST="$CALLER_PWD/notes/.manifest"
}

# ── Confirmation helpers ─────────────────────────────────────

@test "confirm_destructive accepts --yes flag" {
  export usage_yes=true
  run confirm_destructive "Danger?"
  unset usage_yes
  [ "$status" -eq 0 ]
}

@test "confirm_destructive accepts NOTES_YES" {
  export NOTES_YES=1
  run confirm_destructive "Danger?"
  unset NOTES_YES
  [ "$status" -eq 0 ]
}

@test "confirm_destructive accepts MISE_YES" {
  export MISE_YES=yes
  run confirm_destructive "Danger?"
  unset MISE_YES
  [ "$status" -eq 0 ]
}

@test "confirm_destructive requires exact truthy env approval" {
  unset usage_yes MISE_YES
  export NOTES_YES=TRUE
  export NOTES_CONFIRM_TTY="$BATS_TEST_TMPDIR/missing-tty"
  run confirm_destructive "Danger?"
  unset NOTES_YES NOTES_CONFIRM_TTY
  [ "$status" -eq 2 ]
}

@test "confirm_destructive refuses without tty or bypass" {
  unset usage_yes NOTES_YES MISE_YES
  export NOTES_CONFIRM_TTY="$BATS_TEST_TMPDIR/missing-tty"
  run confirm_destructive "Danger?"
  unset NOTES_CONFIRM_TTY
  [ "$status" -eq 2 ]
  [[ "$output" == *"confirmation required"* ]]
  [[ "$output" == *"Re-run with --yes"* ]]
}

# ── Manifest helpers ──────────────────────────────────────────

@test "manifest_id_for_name returns id for known name" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  run manifest_id_for_name "$MANIFEST" "alpha.md"
  [ "$status" -eq 0 ]
  [ "$output" = "abc12345" ]
}

@test "manifest_id_for_name returns nothing for unknown name" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  run manifest_id_for_name "$MANIFEST" "unknown.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "manifest_id_for_name returns nothing when manifest missing" {
  run manifest_id_for_name "$MANIFEST" "alpha.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "manifest_id_for_name does not match partial names" {
  printf 'abc12345\talpha.md\ndef67890\talpha.md.bak\n' > "$MANIFEST"
  run manifest_id_for_name "$MANIFEST" "alpha.md"
  [ "$output" = "abc12345" ]
}

@test "manifest_has_id succeeds for known id" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  manifest_has_id "$MANIFEST" "abc12345"
}

@test "manifest_has_id fails for unknown id" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  ! manifest_has_id "$MANIFEST" "ffffffff"
}

@test "manifest_has_id fails when manifest missing" {
  ! manifest_has_id "$MANIFEST" "abc12345"
}

@test "manifest_has_id does not match partial ids" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  ! manifest_has_id "$MANIFEST" "abc1234"
}

@test "manifest_name_for_id returns name for known id" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  run manifest_name_for_id "$MANIFEST" "abc12345"
  [ "$status" -eq 0 ]
  [ "$output" = "alpha.md" ]
}

@test "manifest_name_for_id returns nothing for unknown id" {
  printf 'abc12345\talpha.md\n' > "$MANIFEST"
  run manifest_name_for_id "$MANIFEST" "ffffffff"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
