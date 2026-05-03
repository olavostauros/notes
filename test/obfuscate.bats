#!/usr/bin/env bats

load test_helper

setup() {
  export CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$CALLER_PWD/notes"

  # Create test notes
  echo -e "---\ntitle: Alpha\ntags: [test]\n---\n# Alpha" > "$CALLER_PWD/notes/alpha.md"
  echo -e "---\ntitle: Beta\ntags: [test]\n---\n# Beta" > "$CALLER_PWD/notes/beta.md"
  echo -e "---\ntitle: Gamma\ntags: [test]\n---\n# Gamma" > "$CALLER_PWD/notes/gamma.txt"

  # git init and commit so git mv works
  git -C "$CALLER_PWD" init -q
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "init"
}

# --- Core obfuscation ---

@test "obfuscate renames files to hex IDs" {
  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Obfuscated 3 file(s)"* ]]

  # Original files should be gone
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/beta.md" ]
  [ ! -f "$CALLER_PWD/notes/gamma.txt" ]

  # Manifest should exist with 3 entries
  [ -f "$CALLER_PWD/notes/.manifest" ]
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
}

@test "obfuscate creates extensionless files" {
  notes obfuscate

  for f in "$CALLER_PWD/notes/"*; do
    [ ! -f "$f" ] && continue
    base=$(basename "$f")
    [[ "$base" != *.* ]]
  done
}

@test "obfuscate generates 8-char hex IDs" {
  notes obfuscate

  while IFS=$'\t' read -r id name; do
    [[ "$id" =~ ^[0-9a-f]{8}$ ]]
  done < "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate preserves file content" {
  notes obfuscate

  id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  [[ "$(cat "$CALLER_PWD/notes/$id")" == *"# Alpha"* ]]
}

@test "obfuscate is idempotent" {
  notes obfuscate

  manifest_before=$(cat "$CALLER_PWD/notes/.manifest")
  files_before=$(ls "$CALLER_PWD/notes/" | sort)

  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to obfuscate"* ]]

  [ "$(cat "$CALLER_PWD/notes/.manifest")" = "$manifest_before" ]
  [ "$(ls "$CALLER_PWD/notes/" | sort)" = "$files_before" ]
}

@test "obfuscate dry-run shows plan without renaming" {
  run notes obfuscate --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.md"* ]]

  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/.manifest" ]
}

@test "scoped obfuscate dry-run shows existing manifest ID for readable file" {
  notes obfuscate
  alpha_id=$(grep $'\talpha\.md$' "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate

  run notes obfuscate --dry-run alpha.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.md → $alpha_id"* ]]
  [[ "$output" != *"alpha.md → (will be assigned)"* ]]

  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/$alpha_id" ]
}

@test "scoped obfuscate dry-run skips already-obfuscated IDs" {
  notes obfuscate
  alpha_id=$(grep $'\talpha\.md$' "$CALLER_PWD/notes/.manifest" | cut -f1)

  run notes obfuscate --dry-run "$alpha_id"
  [ "$status" -eq 0 ]
  [[ "$output" != *"$alpha_id"* ]]
  [[ "$output" != *"will be assigned"* ]]

  [ -f "$CALLER_PWD/notes/$alpha_id" ]
}

@test "obfuscate handles new files added after initial obfuscation" {
  notes obfuscate

  echo -e "---\ntitle: Delta\n---\n# Delta" > "$CALLER_PWD/notes/delta.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add delta"

  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"delta.md"* ]]
  [[ "$output" == *"Obfuscated 1 file(s)"* ]]

  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 4 ]
  [ ! -f "$CALLER_PWD/notes/delta.md" ]
}

# --- Scoped obfuscation from deobfuscated state ---
#
# Regression: scoped `notes obfuscate <file>` used to rebuild the manifest by
# checking which obfuscated IDs exist on disk. In the deobfuscated working
# tree, only the just-obfuscated file's ID is on disk — the rest are readable
# names — so the manifest got truncated to one entry, losing all other
# mappings. The staleness check must treat an entry as live if *either* its
# obfuscated id or its readable name is on disk.

@test "scoped obfuscate from deobfuscated state preserves manifest entries" {
  notes obfuscate
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
  beta_id=$(grep $'\tbeta\.md$' "$CALLER_PWD/notes/.manifest" | cut -f1)
  gamma_id=$(grep $'\tgamma\.txt$' "$CALLER_PWD/notes/.manifest" | cut -f1)

  # Drop to deobfuscated state — all files at readable names, none at IDs.
  notes deobfuscate

  # Scoped obfuscate of just one file (simulates the pre-commit hook path).
  run notes obfuscate alpha.md
  [ "$status" -eq 0 ]

  # Manifest must still have all three entries, and beta/gamma must keep their
  # original IDs (stable across the scoped op).
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
  grep -q $'\talpha\.md$' "$CALLER_PWD/notes/.manifest"
  grep -q "^${beta_id}"$'\t''beta\.md$' "$CALLER_PWD/notes/.manifest"
  grep -q "^${gamma_id}"$'\t''gamma\.txt$' "$CALLER_PWD/notes/.manifest"

  # beta and gamma stay on disk under readable names (scoped op must not touch
  # them).
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]
}

@test "full obfuscate from fully-deobfuscated state preserves manifest entries" {
  notes obfuscate
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
  alpha_id=$(grep $'\talpha\.md$' "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate
  # Full obfuscate with no args — should find all three readable files and
  # restore them to their known IDs without dropping manifest entries.
  run notes obfuscate
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
  [ -f "$CALLER_PWD/notes/$alpha_id" ]
}

# --- Stale manifest cleanup ---

@test "obfuscate removes stale entries for deleted files" {
  notes obfuscate
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]

  # Delete a file while deobfuscated
  notes deobfuscate
  rm "$CALLER_PWD/notes/alpha.md"

  notes obfuscate

  # Manifest should have 2 entries, not 3
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 2 ]
  ! grep -q "alpha.md" "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate handles renamed files as delete + new" {
  notes obfuscate
  alpha_id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate
  mv "$CALLER_PWD/notes/alpha.md" "$CALLER_PWD/notes/alpha-v2.md"

  notes obfuscate

  # Old entry gone, new entry present
  ! grep -q "alpha.md" "$CALLER_PWD/notes/.manifest"
  grep -q "alpha-v2.md" "$CALLER_PWD/notes/.manifest"

  # New file gets a different ID (old one freed)
  new_id=$(grep "alpha-v2.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ -f "$CALLER_PWD/notes/$new_id" ]
}

# --- Same filename in different subdirectories ---

@test "obfuscate handles same filename in different subdirectories" {
  mkdir -p "$CALLER_PWD/notes/a" "$CALLER_PWD/notes/b"
  echo -e "---\ntitle: Foo A\n---" > "$CALLER_PWD/notes/a/foo.md"
  echo -e "---\ntitle: Foo B\n---" > "$CALLER_PWD/notes/b/foo.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add same-name files in subdirs"

  notes obfuscate

  # Both should be in manifest with different IDs
  grep -q "a/foo.md" "$CALLER_PWD/notes/.manifest"
  grep -q "b/foo.md" "$CALLER_PWD/notes/.manifest"

  id_a=$(grep "a/foo.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  id_b=$(grep "b/foo.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ "$id_a" != "$id_b" ]

  # Both files exist in notes root
  [ -f "$CALLER_PWD/notes/$id_a" ]
  [ -f "$CALLER_PWD/notes/$id_b" ]

  # Subdirectories should be gone
  [ ! -d "$CALLER_PWD/notes/a" ]
  [ ! -d "$CALLER_PWD/notes/b" ]

  # Content preserved
  [[ "$(cat "$CALLER_PWD/notes/$id_a")" == *"Foo A"* ]]
  [[ "$(cat "$CALLER_PWD/notes/$id_b")" == *"Foo B"* ]]
}

# --- Stable IDs across cycles ---

@test "obfuscate reuses IDs from preserved manifest" {
  notes obfuscate
  manifest_first=$(cat "$CALLER_PWD/notes/.manifest")

  notes deobfuscate
  notes obfuscate

  manifest_second=$(cat "$CALLER_PWD/notes/.manifest")
  [ "$manifest_first" = "$manifest_second" ]

  # Verify files are actually obfuscated, not just manifest match
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/beta.md" ]
  [ ! -f "$CALLER_PWD/notes/gamma.txt" ]
}

@test "obfuscate after deobfuscate renames files to their known IDs" {
  notes obfuscate
  alpha_id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/$alpha_id" ]

  notes obfuscate
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/$alpha_id" ]

  # Content survived the round-trip
  [[ "$(cat "$CALLER_PWD/notes/$alpha_id")" == *"# Alpha"* ]]
}

# --- Flatten + recurse ---

@test "obfuscate flattens subdirectory files into notes root" {
  mkdir -p "$CALLER_PWD/notes/sub"
  echo -e "---\ntitle: Deep\n---\n# Deep" > "$CALLER_PWD/notes/sub/deep.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add subdir note"

  notes obfuscate

  # Subdirectory should be gone (emptied and cleaned up)
  [ ! -d "$CALLER_PWD/notes/sub" ]

  # Manifest should have relative path
  grep -q "sub/deep.md" "$CALLER_PWD/notes/.manifest"

  # All files should be in notes root
  while IFS=$'\t' read -r id name; do
    [ -f "$CALLER_PWD/notes/$id" ]
  done < "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate flattens nested subdirectories" {
  mkdir -p "$CALLER_PWD/notes/a/b/c"
  echo -e "---\ntitle: Nested\n---" > "$CALLER_PWD/notes/a/b/c/nested.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add nested note"

  notes obfuscate

  [ ! -d "$CALLER_PWD/notes/a" ]
  grep -q "a/b/c/nested.md" "$CALLER_PWD/notes/.manifest"
}

# --- Deobfuscate ---

@test "deobfuscate restores original filenames" {
  notes obfuscate
  run notes deobfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restored 3 file(s)"* ]]

  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]
}

@test "deobfuscate preserves manifest for stable IDs" {
  notes obfuscate
  notes deobfuscate

  [ -f "$CALLER_PWD/notes/.manifest" ]
}

@test "deobfuscate recreates subdirectories" {
  mkdir -p "$CALLER_PWD/notes/sub"
  echo -e "---\ntitle: Deep\n---\n# Deep" > "$CALLER_PWD/notes/sub/deep.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add subdir note"

  notes obfuscate
  [ ! -d "$CALLER_PWD/notes/sub" ]

  notes deobfuscate
  [ -f "$CALLER_PWD/notes/sub/deep.md" ]
  [[ "$(cat "$CALLER_PWD/notes/sub/deep.md")" == *"# Deep"* ]]
}

@test "deobfuscate preserves file content" {
  notes obfuscate
  notes deobfuscate

  [[ "$(cat "$CALLER_PWD/notes/alpha.md")" == *"# Alpha"* ]]
  [[ "$(cat "$CALLER_PWD/notes/gamma.txt")" == *"# Gamma"* ]]
}

@test "deobfuscate fails without manifest" {
  run notes deobfuscate
  [ "$status" -ne 0 ]
  [[ "$output" == *"no manifest found"* ]]
}

@test "deobfuscate dry-run shows plan without renaming" {
  notes obfuscate
  id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)

  run notes deobfuscate -- --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.md"* ]]

  [ -f "$CALLER_PWD/notes/$id" ]
}

@test "round-trip preserves all content and metadata" {
  notes obfuscate
  notes deobfuscate

  run farts get title "$CALLER_PWD/notes/alpha.md"
  [ "$output" = "Alpha" ]

  run farts get title "$CALLER_PWD/notes/beta.md"
  [ "$output" = "Beta" ]
}

# --- Pre-commit hook ---

# --- Hook installation ---

@test "install-hooks installs obfuscation pre-commit hook" {
  notes install-hooks

  [ -x "$CALLER_PWD/.git/hooks/pre-commit" ]
  grep -q "Generic hook dispatcher" "$CALLER_PWD/.git/hooks/pre-commit"
  [ -x "$CALLER_PWD/.git/hooks/pre-commit.d/obfuscation" ]
  grep -q "manifest" "$CALLER_PWD/.git/hooks/pre-commit.d/obfuscation"
}

@test "deobfuscate does not install hooks" {
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscate"

  notes deobfuscate

  [ ! -d "$CALLER_PWD/.git/hooks/pre-commit.d" ]
}

@test "deobfuscate dry-run does not install hook" {
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscate"

  notes deobfuscate -- --dry-run

  [ ! -d "$CALLER_PWD/.git/hooks/pre-commit.d" ]
}

@test "dispatcher runs all hooks in pre-commit.d" {
  # Set up dispatcher with two hooks — one passes, one would fail
  mkdir -p "$CALLER_PWD/.git/hooks/pre-commit.d"
  cat > "$CALLER_PWD/.git/hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
set -eo pipefail
HOOK_DIR="$(dirname "$0")/pre-commit.d"
for hook in "$HOOK_DIR"/*; do
  [ -x "$hook" ] && "$hook" || exit $?
done
EOF
  chmod +x "$CALLER_PWD/.git/hooks/pre-commit"

  # Hook that passes
  echo '#!/usr/bin/env bash' > "$CALLER_PWD/.git/hooks/pre-commit.d/pass"
  echo 'exit 0' >> "$CALLER_PWD/.git/hooks/pre-commit.d/pass"
  chmod +x "$CALLER_PWD/.git/hooks/pre-commit.d/pass"

  # Hook that fails
  echo '#!/usr/bin/env bash' > "$CALLER_PWD/.git/hooks/pre-commit.d/fail"
  echo 'echo "blocked" >&2; exit 1' >> "$CALLER_PWD/.git/hooks/pre-commit.d/fail"
  chmod +x "$CALLER_PWD/.git/hooks/pre-commit.d/fail"

  echo "test" > "$CALLER_PWD/notes/test-file.md"
  git -C "$CALLER_PWD" add notes/test-file.md

  run git -C "$CALLER_PWD" commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"blocked"* ]]
}

# --- Pre-commit hook behavior ---

# These tests exercise the pre-commit hook directly. Auto-obfuscate is the
# default hook mode; using `git commit` during setup would fire the hook and
# obfuscate files behind the test's back, leaving nothing for the explicit
# `notes obfuscate` step to do. Use --no-verify on setup commits to keep the
# tests in control of when obfuscation happens.

@test "pre-commit hook rejects un-obfuscated files in guard mode" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit --no-verify -q -m "setup"

  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit --no-verify -q -m "obfuscated"

  echo -e "---\ntitle: Sneaky\n---\n# Sneaky" > "$CALLER_PWD/notes/sneaky.md"
  git -C "$CALLER_PWD" add notes/sneaky.md

  NOTES_OBFUSCATE_HOOK=guard run git -C "$CALLER_PWD" commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-obfuscated filenames"* ]]
  [[ "$output" == *"sneaky.md"* ]]
}

@test "pre-commit hook allows obfuscated files" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit --no-verify -q -m "setup"

  notes obfuscate
  git -C "$CALLER_PWD" add -A

  run git -C "$CALLER_PWD" commit -m "should succeed"
  [ "$status" -eq 0 ]
}

@test "pre-commit hook rejects staged renames in guard mode" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit --no-verify -q -m "setup"

  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit --no-verify -q -m "obfuscated"

  # After committing the obfuscated state, the post-commit hook
  # deobfuscates the working tree and adds readable names to
  # .git/info/exclude (clean-status mechanism from notes#43). A plain
  # `git add notes/` now no-ops. To simulate someone trying to stage a
  # deobfuscated rename anyway, we force-add the readable name.
  git -C "$CALLER_PWD" add -f notes/alpha.md

  # The hook should reject this in guard mode
  NOTES_OBFUSCATE_HOOK=guard run git -C "$CALLER_PWD" commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-obfuscated filenames"* ]]
  [[ "$output" == *"alpha.md"* ]]
}

@test "pre-commit hook auto-obfuscates by default" {
  # Obfuscate and commit the obfuscated state
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"

  # Deobfuscate + install hooks explicitly
  notes deobfuscate
  notes install-hooks

  # Add a new deobfuscated file + stage everything
  echo -e "---\ntitle: Sneaky\n---\n# Sneaky" > "$CALLER_PWD/notes/sneaky.md"
  git -C "$CALLER_PWD" add -A

  # Should succeed — hook auto-obfuscates before commit
  run git -C "$CALLER_PWD" commit -m "should succeed"
  [ "$status" -eq 0 ]

  # The committed tree should have obfuscated filenames
  # (post-commit hook deobfuscates the working tree, so check git not disk)
  local committed_files
  committed_files=$(git -C "$CALLER_PWD" show --name-only --format='' HEAD -- notes/)
  ! echo "$committed_files" | grep -q "alpha.md"
  ! echo "$committed_files" | grep -q "sneaky.md"

  # Manifest should have all entries
  grep -q "sneaky.md" "$CALLER_PWD/notes/.manifest"
  grep -q "alpha.md" "$CALLER_PWD/notes/.manifest"
}

# --- Post-commit hook ---

@test "install-hooks installs post-commit deobfuscation hook" {
  notes install-hooks

  [ -x "$CALLER_PWD/.git/hooks/post-commit" ]
  grep -q "Generic hook dispatcher" "$CALLER_PWD/.git/hooks/post-commit"
  [ -x "$CALLER_PWD/.git/hooks/post-commit.d/deobfuscation" ]
  grep -q "manifest" "$CALLER_PWD/.git/hooks/post-commit.d/deobfuscation"
}

@test "post-commit hook deobfuscates working tree after commit" {
  # Obfuscate and commit initial state
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"

  # Deobfuscate + install hooks explicitly
  notes deobfuscate
  notes install-hooks

  # Add a new file and commit — hooks should handle the round-trip
  echo -e "---\ntitle: New Note\n---\n# New" > "$CALLER_PWD/notes/new-note.md"
  git -C "$CALLER_PWD" add notes/new-note.md
  git -C "$CALLER_PWD" commit -m "add new note"

  # Working tree should have readable filenames (post-commit deobfuscated)
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]
  [ -f "$CALLER_PWD/notes/new-note.md" ]

  # Committed tree should have obfuscated filenames
  local committed_files
  committed_files=$(git -C "$CALLER_PWD" show --name-only --format='' HEAD -- notes/)
  ! echo "$committed_files" | grep -q "alpha.md"
  ! echo "$committed_files" | grep -q "new-note.md"
}

@test "post-commit hook preserves file content after round-trip" {
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"

  notes deobfuscate
  notes install-hooks

  echo -e "---\ntitle: Fresh\n---\n# Fresh content" > "$CALLER_PWD/notes/fresh.md"
  git -C "$CALLER_PWD" add notes/fresh.md
  git -C "$CALLER_PWD" commit -m "add fresh"

  # Content should survive the obfuscate→deobfuscate round-trip
  [[ "$(cat "$CALLER_PWD/notes/alpha.md")" == *"# Alpha"* ]]
  [[ "$(cat "$CALLER_PWD/notes/fresh.md")" == *"# Fresh content"* ]]
}

@test "post-commit hook is no-op when files are not obfuscated" {
  # Install hooks — no manifest exists, so hooks should be no-ops
  notes install-hooks

  # Commit should succeed even though post-commit hook exists
  echo "change" >> "$CALLER_PWD/notes/alpha.md"
  git -C "$CALLER_PWD" add -A
  run git -C "$CALLER_PWD" commit -m "should work fine"
  [ "$status" -eq 0 ]
}

# --- Bash 3.2 compatibility ---

@test "obfuscate works without associative arrays (bash 3.2)" {
  # Verify no declare -A in task scripts or hook templates
  ! grep -q 'declare -A' "$MISE_CONFIG_ROOT/.mise/tasks/obfuscate"
  ! grep -q 'declare -A' "$MISE_CONFIG_ROOT/.mise/tasks/deobfuscate"
  ! grep -q 'declare -A' "$MISE_CONFIG_ROOT/hooks/obfuscation.template"
  ! grep -q 'declare -A' "$MISE_CONFIG_ROOT/hooks/post-commit-deobfuscate.template"
}

@test "obfuscate succeeds with single file" {
  # Minimal case — catches set -e failures in manifest lookups
  rm "$CALLER_PWD/notes/beta.md" "$CALLER_PWD/notes/gamma.txt"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "remove extras"

  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Obfuscated 1 file(s)"* ]]
}

@test "pre-commit hook allows commits when no manifest exists" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "setup"

  echo -e "---\ntitle: Normal\n---" > "$CALLER_PWD/notes/normal.md"
  git -C "$CALLER_PWD" add notes/normal.md

  run git -C "$CALLER_PWD" commit -m "should succeed"
  [ "$status" -eq 0 ]
}

# --- deobfuscate never stages ---

@test "deobfuscate restores names without staging" {
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"

  notes deobfuscate

  # Working tree has readable names
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]

  # Index is clean (no staged changes)
  local staged
  staged=$(git -C "$CALLER_PWD" diff --cached --name-status)
  [ -z "$staged" ]
}

@test "obfuscate works when working tree is deobfuscated but index has obfuscated names" {
  # This is the state after deobfuscate
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"
  notes deobfuscate

  # Now obfuscate should restore obfuscated names and stage them
  run notes obfuscate
  [ "$status" -eq 0 ]

  # All files should be obfuscated on disk
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/beta.md" ]

  # Manifest entries should use the same IDs (stable)
  local id_alpha id_beta
  id_alpha=$(grep 'alpha.md' "$CALLER_PWD/notes/.manifest" | cut -f1)
  id_beta=$(grep 'beta.md' "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ -f "$CALLER_PWD/notes/$id_alpha" ]
  [ -f "$CALLER_PWD/notes/$id_beta" ]
}

@test "full commit cycle: deobfuscated working tree stays clean" {
  # Set up obfuscated repo with hooks
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"
  notes deobfuscate
  notes install-hooks

  # Edit a file and commit via hooks
  echo "edited" >> "$CALLER_PWD/notes/alpha.md"
  notes stage alpha.md
  run git -C "$CALLER_PWD" commit -m "edit alpha"
  [ "$status" -eq 0 ]

  # Committed tree should have obfuscated names
  local committed_files
  committed_files=$(git -C "$CALLER_PWD" show --name-only --format='' HEAD -- notes/)
  ! echo "$committed_files" | grep -q "alpha.md"

  # Working tree should have readable names (post-commit deobfuscated)
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [[ "$(cat "$CALLER_PWD/notes/alpha.md")" == *"edited"* ]]

  # Index should be clean
  local staged
  staged=$(git -C "$CALLER_PWD" diff --cached --name-status)
  [ -z "$staged" ]
}

# --- Post-merge hook ---

@test "install-hooks installs post-merge deobfuscation hook" {
  notes install-hooks

  [ -x "$CALLER_PWD/.git/hooks/post-merge" ]
  grep -q "Generic hook dispatcher" "$CALLER_PWD/.git/hooks/post-merge"
  [ -x "$CALLER_PWD/.git/hooks/post-merge.d/deobfuscation" ]
  grep -q "manifest" "$CALLER_PWD/.git/hooks/post-merge.d/deobfuscation"
}

# --- Scoped obfuscation (variadic args) ---

@test "obfuscate with args only processes specified files" {
  notes obfuscate alpha.md beta.md

  # Specified files should be obfuscated
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/beta.md" ]

  # Unspecified file should remain
  [ -f "$CALLER_PWD/notes/gamma.txt" ]

  # Manifest should have entries for obfuscated files
  grep -q "alpha.md" "$CALLER_PWD/notes/.manifest"
  grep -q "beta.md" "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate with args handles notes-dir prefix" {
  notes obfuscate notes/alpha.md

  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]
}

@test "obfuscate with args re-obfuscates known files" {
  # First obfuscate all, then deobfuscate
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"
  notes deobfuscate

  # Re-obfuscate only one file
  notes obfuscate alpha.md

  # alpha should be obfuscated, others still readable
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]

  # ID should be stable (same as manifest)
  local id_alpha
  id_alpha=$(grep 'alpha.md' "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ -f "$CALLER_PWD/notes/$id_alpha" ]
}

@test "deobfuscate with args only processes specified IDs" {
  notes obfuscate

  local id_alpha
  id_alpha=$(grep 'alpha.md' "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate "$id_alpha"

  # alpha should be restored
  [ -f "$CALLER_PWD/notes/alpha.md" ]

  # Others should remain obfuscated
  local id_beta
  id_beta=$(grep 'beta.md' "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ -f "$CALLER_PWD/notes/$id_beta" ]
}

@test "deobfuscate with args warns on unknown ID" {
  notes obfuscate

  run notes deobfuscate nonexistent123
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to deobfuscate"* ]] || [[ "$output" == *"Warning: unknown"* ]]
}

@test "deobfuscate scoped sets assume-unchanged only on deobfuscated IDs" {
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"

  local alpha_id beta_id
  alpha_id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  beta_id=$(grep "beta.md" "$CALLER_PWD/notes/.manifest" | cut -f1)

  # Deobfuscate only alpha
  notes deobfuscate "$alpha_id"

  # alpha's obfuscated ID should be assume-unchanged
  run git -C "$CALLER_PWD" ls-files -v "notes/$alpha_id"
  [[ "$output" == h* ]]

  # beta's obfuscated ID should NOT be assume-unchanged (still tracked normally)
  run git -C "$CALLER_PWD" ls-files -v "notes/$beta_id"
  [[ "$output" == H* ]]
}

@test "pre-commit hook only obfuscates staged files" {
  # Set up: obfuscate, commit, then deobfuscate + install hooks
  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q --no-verify -m "obfuscated"
  notes deobfuscate
  notes install-hooks
  # Working tree: readable names. Index: obfuscated names matching HEAD.

  # Edit one file, stage only that one
  echo "change" >> "$CALLER_PWD/notes/alpha.md"
  git -C "$CALLER_PWD" add -f notes/alpha.md

  # Capture stderr from commit (hooks print rename operations there)
  local stderr_log="$BATS_TEST_TMPDIR/commit-stderr"
  git -C "$CALLER_PWD" commit -m "edit one file" 2>"$stderr_log"

  cat "$stderr_log" >&2

  # Count how many files the pre-commit hook obfuscated
  local obfuscated_count
  obfuscated_count=$(sed -n 's/.*Auto-obfuscating \([0-9]*\) file.*/\1/p' "$stderr_log")
  echo "auto-obfuscated: ${obfuscated_count:-none}" >&2

  # Should obfuscate exactly 1 file (the staged one)
  [ -n "$obfuscated_count" ]
  [ "$obfuscated_count" -eq 1 ]
}

@test "deobfuscate succeeds when readable name already exists on disk" {
  # Simulate the bug: both obfuscated ID and readable name exist
  notes obfuscate
  local alpha_id
  alpha_id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  [ -f "$CALLER_PWD/notes/$alpha_id" ]

  # Create a stale readable copy (simulates bad commit state)
  echo "stale content" > "$CALLER_PWD/notes/alpha.md"

  # Deobfuscate should overwrite the stale copy, not fail
  run notes deobfuscate
  [ "$status" -eq 0 ]

  # Readable file has the authoritative content (from obfuscated copy)
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [[ "$(cat "$CALLER_PWD/notes/alpha.md")" == *"# Alpha"* ]]
  [[ "$(cat "$CALLER_PWD/notes/alpha.md")" != *"stale"* ]]
}

# ── Refuse re-obfuscation of already-hex-named files ──────────

@test "obfuscate refuses files whose basename is an 8-hex id" {
  # Simulate the broken state we saw on den/fold through April 2026:
  # an obfuscated file exists on disk, but the manifest has lost its entry.
  # Without this guard, `notes obfuscate` would treat the hex file as
  # unobfuscated, generate a fresh random id, and create a duplicate blob.
  mkdir -p "$CALLER_PWD/notes"
  echo "---
title: orphan" > "$CALLER_PWD/notes/deadbeef"
  # No manifest entry for deadbeef — simulates the lost-mapping case

  run notes obfuscate "deadbeef"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to obfuscate"* ]]
  [[ "$output" == *"deadbeef"* ]]

  # File must not have been renamed
  [ -f "$CALLER_PWD/notes/deadbeef" ]
}

@test "obfuscate refuses hex-named file in full scan mode" {
  # Same guard, but via unscoped `notes obfuscate` (scans all files)
  mkdir -p "$CALLER_PWD/notes"
  cat > "$CALLER_PWD/notes/alpha.md" <<EOT
---
title: Alpha
---
alpha
EOT
  echo "orphan" > "$CALLER_PWD/notes/cafebabe"

  run notes obfuscate
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to obfuscate"* ]]
  [[ "$output" == *"cafebabe"* ]]

  # alpha.md also shouldn't have been renamed (the guard aborts the operation)
  [ -f "$CALLER_PWD/notes/alpha.md" ]
}

@test "obfuscate allows files with hex prefix but non-hex tail" {
  # Don't false-positive on names that happen to start with hex
  mkdir -p "$CALLER_PWD/notes"
  cat > "$CALLER_PWD/notes/abc123xy.md" <<EOT
---
title: abc
---
content
EOT

  run notes obfuscate
  [ "$status" -eq 0 ]
  # File was renamed to a real hex id (manifest has entry)
  [ -f "$CALLER_PWD/notes/.manifest" ]
  grep -q "abc123xy.md" "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate allows files whose basename is hex but has an extension" {
  # `deadbeef.md` is a valid readable filename; guard only fires on bare 8-hex
  mkdir -p "$CALLER_PWD/notes"
  cat > "$CALLER_PWD/notes/deadbeef.md" <<EOT
---
title: Dead Beef
---
content
EOT

  run notes obfuscate
  [ "$status" -eq 0 ]
  grep -q "deadbeef.md" "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate refuses hex-named file in a subdirectory" {
  # The guard uses basename(), so nested paths must still be caught.
  mkdir -p "$CALLER_PWD/notes/sub"
  echo "orphan" > "$CALLER_PWD/notes/sub/cafebabe"

  run notes obfuscate "sub/cafebabe"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to obfuscate"* ]]
  [[ "$output" == *"cafebabe"* ]]

  # File must not have been renamed
  [ -f "$CALLER_PWD/notes/sub/cafebabe" ]
}

@test "obfuscate hex guard: uppercase basename behavior" {
  # The guard regex is lowercase-only ([a-f0-9]). On a case-insensitive
  # filesystem (macOS APFS default, NTFS), 'DEADBEEF' and 'deadbeef' collide
  # — the guard won't fire because uppercase doesn't match, even though
  # the file on disk is the same as an obfuscated lowercase name.
  # On a case-sensitive filesystem, they're truly different files and the
  # uppercase one is just a regular filename.
  #
  # This test documents the contract: the guard fires only on lowercase
  # hex. If the ID generator ever produces uppercase, or if we want to
  # catch the case-insensitive-FS collision, the regex must change.
  mkdir -p "$CALLER_PWD/notes"
  echo "uppercase" > "$CALLER_PWD/notes/DEADBEEF"
  # No .md extension; basename is 8 chars of uppercase hex
  # Note: the note has no title in frontmatter, which is fine — we're testing
  # the guard path, not frontmatter parsing.
  cat > "$CALLER_PWD/notes/DEADBEEF" <<'EOT'
---
title: deadbeef
---
content
EOT

  run notes obfuscate "DEADBEEF"
  # Current behavior: uppercase passes through — guard doesn't fire, file
  # gets a fresh random obfuscated ID.
  [ "$status" -eq 0 ]
  # The original uppercase file is renamed (disappeared)
  [ ! -f "$CALLER_PWD/notes/DEADBEEF" ]
  # A new obfuscated entry exists in the manifest
  grep -q "DEADBEEF" "$CALLER_PWD/notes/.manifest" || fail "expected manifest entry for DEADBEEF"
}

@test "obfuscate hex guard: 7-char and 9-char hex pass through" {
  # The guard is {8}, not {7,} or {8,}. Files whose basenames are hex but
  # the wrong length are treated as normal readable filenames. This locks
  # in the boundary in case anyone 'improves' the regex without thinking.
  mkdir -p "$CALLER_PWD/notes"
  cat > "$CALLER_PWD/notes/abcdef0" <<'EOT'
---
title: seven-char
---
EOT
  cat > "$CALLER_PWD/notes/abcdef012" <<'EOT'
---
title: nine-char
---
EOT

  run notes obfuscate
  [ "$status" -eq 0 ]
  # Both files got renamed to obfuscated IDs (guard didn't fire)
  [ ! -f "$CALLER_PWD/notes/abcdef0" ]
  [ ! -f "$CALLER_PWD/notes/abcdef012" ]
  grep -q "abcdef0$" "$CALLER_PWD/notes/.manifest" || fail "expected 7-char entry in manifest"
  grep -q "abcdef012$" "$CALLER_PWD/notes/.manifest" || fail "expected 9-char entry in manifest"
}

@test "obfuscate hex guard: multiple hex-named orphans in full-scan mode (first-hit-only)" {
  # If several hex-named files exist, the guard fires on the first and
  # aborts the entire rename_to_obfuscated call. This documents that
  # behavior: the error message only names ONE of the orphans — the user
  # must iterate. If that changes (e.g., we collect all violations before
  # failing), this test will notice.
  mkdir -p "$CALLER_PWD/notes"
  echo "orphan1" > "$CALLER_PWD/notes/deadbeef"
  echo "orphan2" > "$CALLER_PWD/notes/cafebabe"
  cat > "$CALLER_PWD/notes/real.md" <<'EOT'
---
title: real
---
EOT

  run notes obfuscate
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to obfuscate"* ]]
  # At least one of the two orphans is named in the error
  if [[ "$output" != *"deadbeef"* ]] && [[ "$output" != *"cafebabe"* ]]; then
    fail "expected at least one orphan name in error: $output"
  fi
  # Neither orphan was renamed — the operation aborted
  [ -f "$CALLER_PWD/notes/deadbeef" ]
  [ -f "$CALLER_PWD/notes/cafebabe" ]
  # And real.md wasn't obfuscated either (fail-fast = no partial state)
  [ -f "$CALLER_PWD/notes/real.md" ]
}
