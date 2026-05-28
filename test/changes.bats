#!/usr/bin/env bats

# Tests for notes changes detection and the changes/stage commands.

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  source "$REPO_DIR/lib/common.sh"
  source "$REPO_DIR/lib/obfuscate.sh"
  source "$REPO_DIR/lib/suppress.sh"
  source "$REPO_DIR/lib/changes.sh"

  # Create a git repo with obfuscated notes
  git -C "$NOTES_CALLER_PWD" init -q
  git -C "$NOTES_CALLER_PWD" config user.name "Test"
  git -C "$NOTES_CALLER_PWD" config user.email "test@test.com"

  mkdir -p "$NOTES_CALLER_PWD/notes"
  echo "# Alpha" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Beta" > "$NOTES_CALLER_PWD/notes/beta.md"

  MANIFEST="$NOTES_CALLER_PWD/notes/.manifest"

  # Obfuscate, commit, then deobfuscate (simulates normal state)
  rename_to_obfuscated "$NOTES_CALLER_PWD/notes" > /dev/null
  git -C "$NOTES_CALLER_PWD" add -A
  git -C "$NOTES_CALLER_PWD" commit -q -m "initial"
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  set_status_suppression "$NOTES_CALLER_PWD/notes"
}

# ── detect_changes ────────────────────────────────────────────

@test "detect_changes: no changes when files match HEAD" {
  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_changes: detects modified file" {
  echo "# Alpha modified" > "$NOTES_CALLER_PWD/notes/alpha.md"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"modified"*"alpha.md"* ]]
  # Beta should not appear
  [[ "$output" != *"beta.md"* ]]
}

@test "detect_changes: detects new file not in manifest" {
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new"*"gamma.md"* ]]
}

@test "detect_changes: detects new file in manifest but not in HEAD" {
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"
  # Manifest entry exists but file was never committed
  printf 'cccccccc\tgamma.md\n' >> "$MANIFEST"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"new"*"gamma.md"* ]]
}

@test "detect_changes: detects deleted file" {
  # Remove the readable file and the obfuscated file
  rm "$NOTES_CALLER_PWD/notes/alpha.md"
  local alpha_id
  alpha_id=$(manifest_id_for_name "$MANIFEST" "alpha.md")
  # The obfuscated file shouldn't exist (we're in deobfuscated state)
  # but make sure it's gone
  rm -f "$NOTES_CALLER_PWD/notes/$alpha_id"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"deleted"*"alpha.md"* ]]
}

@test "detect_changes: multiple changes detected" {
  echo "# Alpha modified" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"modified"*"alpha.md"* ]]
  [[ "$output" == *"new"*"gamma.md"* ]]
}

@test "detect_changes: unchanged files not reported" {
  # Make no changes
  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "detect_changes: handles many notes with mixed changes" {
  local i name delete_id

  i=1
  while [ "$i" -le 40 ]; do
    name=$(printf 'note-%02d.md' "$i")
    printf '# Note %02d\n' "$i" > "$NOTES_CALLER_PWD/notes/$name"
    i=$((i + 1))
  done

  rename_to_obfuscated "$NOTES_CALLER_PWD/notes" > /dev/null
  git -C "$NOTES_CALLER_PWD" add -A
  git -C "$NOTES_CALLER_PWD" commit -q -m "add many notes"
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  set_status_suppression "$NOTES_CALLER_PWD/notes"

  printf '# Note 10 edited\n' > "$NOTES_CALLER_PWD/notes/note-10.md"
  printf '# New\n' > "$NOTES_CALLER_PWD/notes/new.md"
  rm "$NOTES_CALLER_PWD/notes/note-20.md"
  delete_id=$(manifest_id_for_name "$MANIFEST" "note-20.md")
  rm -f "$NOTES_CALLER_PWD/notes/$delete_id"

  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"modified"*"note-10.md"* ]]
  [[ "$output" == *"deleted"*"note-20.md"* ]]
  [[ "$output" == *"new"*"new.md"* ]]
  [[ "$output" != *"note-30.md"* ]]
}

@test "detect_changes: preserves tracked-path filter semantics when attrs differ" {
  local repo
  repo="$BATS_TEST_TMPDIR/path-attrs-repo"
  mkdir -p "$repo/notes"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"
  git -C "$repo" config filter.prefix.clean "sed 's/^/clean:/'"
  printf 'notes/???????? filter=prefix\n' > "$repo/.gitattributes"
  echo "# Alpha" > "$repo/notes/alpha.md"
  echo "# Beta" > "$repo/notes/beta.md"

  rename_to_obfuscated "$repo/notes" > /dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "initial with path-specific attrs"
  rename_to_readable "$repo/notes" > /dev/null
  set_status_suppression "$repo/notes"

  run detect_changes "$repo/notes"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  printf '# Alpha edited\n' > "$repo/notes/alpha.md"
  run detect_changes "$repo/notes"
  [ "$status" -eq 0 ]
  [[ "$output" == *"modified"*"alpha.md"* ]]
}

# ── exclude management ────────────────────────────────────────

@test "set_status_suppression adds exclude entries" {
  local repo_root
  repo_root=$(git -C "$NOTES_CALLER_PWD" rev-parse --show-toplevel)
  local exclude="$repo_root/.git/info/exclude"

  # Suppression was already set in setup
  [ -f "$exclude" ]
  grep -q "notes/alpha.md" "$exclude"
  grep -q "notes/beta.md" "$exclude"
  grep -q "# BEGIN notes-obfuscation" "$exclude"
  grep -q "# END notes-obfuscation" "$exclude"
}

@test "set_status_suppression gives clean git status" {
  # After setup, git status should be clean
  run git -C "$NOTES_CALLER_PWD" status --porcelain
  [ -z "$output" ]
}

@test "clear_status_suppression removes exclude entries" {
  clear_status_suppression "$NOTES_CALLER_PWD/notes"

  local repo_root
  repo_root=$(git -C "$NOTES_CALLER_PWD" rev-parse --show-toplevel)
  local exclude="$repo_root/.git/info/exclude"

  # Managed block should be gone
  if [ -f "$exclude" ]; then
    ! grep -q "notes/alpha.md" "$exclude"
    ! grep -q "# BEGIN notes-obfuscation" "$exclude"
  fi
}

@test "exclude preserves non-managed content" {
  local repo_root
  repo_root=$(git -C "$NOTES_CALLER_PWD" rev-parse --show-toplevel)
  local exclude="$repo_root/.git/info/exclude"

  # Add custom content before the managed block
  local tmp
  tmp=$(mktemp)
  echo "# My custom excludes" > "$tmp"
  echo "build/" >> "$tmp"
  if [ -f "$exclude" ]; then
    cat "$exclude" >> "$tmp"
  fi
  mv "$tmp" "$exclude"

  # Re-run suppression (should preserve custom content)
  clear_status_suppression "$NOTES_CALLER_PWD/notes"
  set_status_suppression "$NOTES_CALLER_PWD/notes"

  grep -q "# My custom excludes" "$exclude"
  grep -q "build/" "$exclude"
  grep -q "notes/alpha.md" "$exclude"
}

@test "scoped set_status_suppression adds only specified entries" {
  # Clear all first
  clear_status_suppression "$NOTES_CALLER_PWD/notes"

  local alpha_id
  alpha_id=$(manifest_id_for_name "$MANIFEST" "alpha.md")

  # Set suppression for just alpha
  set_status_suppression "$NOTES_CALLER_PWD/notes" "$alpha_id"

  local repo_root
  repo_root=$(git -C "$NOTES_CALLER_PWD" rev-parse --show-toplevel)
  local exclude="$repo_root/.git/info/exclude"

  grep -q "notes/alpha.md" "$exclude"
  ! grep -q "notes/beta.md" "$exclude"
}

@test "scoped clear_status_suppression removes only specified entries" {
  local alpha_id
  alpha_id=$(manifest_id_for_name "$MANIFEST" "alpha.md")

  # Clear just alpha
  clear_status_suppression "$NOTES_CALLER_PWD/notes" "$alpha_id"

  local repo_root
  repo_root=$(git -C "$NOTES_CALLER_PWD" rev-parse --show-toplevel)
  local exclude="$repo_root/.git/info/exclude"

  ! grep -q "notes/alpha.md" "$exclude"
  grep -q "notes/beta.md" "$exclude"
}

# ── stage via git add -f ─────────────────────────────────────

@test "git add -f works despite exclude" {
  echo "# Alpha modified" > "$NOTES_CALLER_PWD/notes/alpha.md"

  # Normal git add should fail (file is excluded)
  git -C "$NOTES_CALLER_PWD" add "$NOTES_CALLER_PWD/notes/alpha.md" 2>/dev/null || true
  run git -C "$NOTES_CALLER_PWD" diff --cached --name-only
  [[ "$output" != *"alpha.md"* ]]

  # Force add should work
  git -C "$NOTES_CALLER_PWD" add -f "$NOTES_CALLER_PWD/notes/alpha.md"
  run git -C "$NOTES_CALLER_PWD" diff --cached --name-only
  [[ "$output" == *"alpha.md"* ]]
}

@test "notes stage: no args skips new notes but stages modified notes" {
  echo "# Alpha modified" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"

  run notes stage
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged: alpha.md"* ]]
  [[ "$output" == *"Skipped 1 new note(s)"* ]]
  [[ "$output" == *"new: gamma.md"* ]]

  run git -C "$NOTES_CALLER_PWD" diff --cached --name-only
  [[ "$output" == *"notes/alpha.md"* ]]
  [[ "$output" != *"notes/gamma.md"* ]]
}

@test "notes stage: explicit file stages a new note" {
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"

  run notes stage gamma.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged: gamma.md"* ]]

  run git -C "$NOTES_CALLER_PWD" diff --cached --name-only
  [[ "$output" == *"notes/gamma.md"* ]]
}

@test "notes stage: refuses dual-present differing readable and obfuscated pair" {
  local alpha_id
  alpha_id=$(manifest_id_for_name "$MANIFEST" "alpha.md")

  echo "# Alpha local edit" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Alpha incoming upstream" > "$NOTES_CALLER_PWD/notes/$alpha_id"

  run notes stage alpha.md
  [ "$status" -ne 0 ]
  [[ "$output" == *"incomplete deobfuscation"* ]]
  [[ "$output" == *"alpha.md"* ]]
  [[ "$output" == *"notes deobfuscate"* ]]
  [[ "$output" == *"notes changes alpha.md"* ]]

  run git -C "$NOTES_CALLER_PWD" diff --cached --name-only
  [[ "$output" != *"notes/alpha.md"* ]]
}

@test "notes stage: no args skips readable files left from another branch" {
  local repo="$BATS_TEST_TMPDIR/branch-repo"
  mkdir -p "$repo/notes"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.name "Test"
  git -C "$repo" config user.email "test@test.com"

  echo "# Alpha" > "$repo/notes/alpha.md"
  rename_to_obfuscated "$repo/notes" > /dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "add alpha"
  rename_to_readable "$repo/notes" > /dev/null
  set_status_suppression "$repo/notes"

  git -C "$repo" branch feature

  echo "# Beta" > "$repo/notes/beta.md"
  rename_to_obfuscated "$repo/notes" > /dev/null
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "add beta on main"
  rename_to_readable "$repo/notes" > /dev/null
  set_status_suppression "$repo/notes"

  git -C "$repo" checkout -q feature
  [ -f "$repo/notes/beta.md" ]
  echo "alpha edit" >> "$repo/notes/alpha.md"

  NOTES_CALLER_PWD="$repo" run notes stage
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged: alpha.md"* ]]
  [[ "$output" == *"Skipped 1 new note(s)"* ]]
  [[ "$output" == *"new: beta.md"* ]]

  run git -C "$repo" diff --cached --name-only
  [[ "$output" == *"notes/alpha.md"* ]]
  [[ "$output" != *"notes/beta.md"* ]]
}

@test "notes stage: skipped new manifest entry does not leak through pre-commit hook" {
  source "$REPO_DIR/lib/hooks.sh"
  install_obfuscation_hook
  install_deobfuscation_hook

  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"
  printf 'cccccccc\tgamma.md\n' >> "$MANIFEST"
  echo "# Alpha modified" > "$NOTES_CALLER_PWD/notes/alpha.md"

  run notes stage
  [ "$status" -eq 0 ]
  [[ "$output" == *"staged: alpha.md"* ]]
  [[ "$output" == *"Skipped 1 new note(s)"* ]]
  [[ "$output" == *"new: gamma.md"* ]]

  git -C "$NOTES_CALLER_PWD" commit -q -m "update alpha"

  run git -C "$NOTES_CALLER_PWD" cat-file --filters HEAD:notes/.manifest
  [[ "$output" == *"alpha.md"* ]]
  [[ "$output" != *"gamma.md"* ]]

  run git -C "$NOTES_CALLER_PWD" show --name-only --format= HEAD
  [[ "$output" != *"gamma"* ]]
}

# ── full lifecycle ────────────────────────────────────────────

@test "full cycle: edit → stage → commit → clean status" {
  # Install hooks so post-commit deobfuscates
  source "$REPO_DIR/lib/hooks.sh"
  install_obfuscation_hook
  install_deobfuscation_hook

  # Verify clean status before edit
  run git -C "$NOTES_CALLER_PWD" status --porcelain
  [ -z "$output" ]

  # Edit a note
  echo "# Alpha v2" > "$NOTES_CALLER_PWD/notes/alpha.md"

  # git status should still be clean (exclude hides the change)
  run git -C "$NOTES_CALLER_PWD" status --porcelain
  [ -z "$output" ]

  # But detect_changes should see it
  run detect_changes "$NOTES_CALLER_PWD/notes"
  [[ "$output" == *"modified"*"alpha.md"* ]]

  # Stage via notes stage
  notes stage alpha.md

  # Commit — hooks handle obfuscation + deobfuscation
  git -C "$NOTES_CALLER_PWD" commit -q -m "update alpha"

  # After commit, files should be deobfuscated
  [ -f "$NOTES_CALLER_PWD/notes/alpha.md" ]
  [[ "$(cat "$NOTES_CALLER_PWD/notes/alpha.md")" == *"Alpha v2"* ]]

  # Status should be clean again
  run git -C "$NOTES_CALLER_PWD" status --porcelain
  [ -z "$output" ]

  # No changes detected
  run detect_changes "$NOTES_CALLER_PWD/notes"
  [ -z "$output" ]
}
