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
  run notes obfuscate -- --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.md"* ]]

  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/.manifest" ]
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

# --- Stale manifest cleanup ---

@test "obfuscate removes stale entries for deleted files" {
  notes obfuscate
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]

  # Delete a file while deobfuscated
  notes deobfuscate
  git -C "$CALLER_PWD" rm "$CALLER_PWD/notes/alpha.md"
  git -C "$CALLER_PWD" commit -q -m "delete alpha"

  notes obfuscate

  # Manifest should have 2 entries, not 3
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 2 ]
  ! grep -q "alpha.md" "$CALLER_PWD/notes/.manifest"
}

@test "obfuscate handles renamed files as delete + new" {
  notes obfuscate
  alpha_id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)

  notes deobfuscate
  git -C "$CALLER_PWD" mv "$CALLER_PWD/notes/alpha.md" "$CALLER_PWD/notes/alpha-v2.md"
  git -C "$CALLER_PWD" commit -q -m "rename alpha"

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

@test "pre-commit hook rejects un-obfuscated files when manifest exists" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "setup"

  notes obfuscate
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "obfuscated"

  echo -e "---\ntitle: Sneaky\n---\n# Sneaky" > "$CALLER_PWD/notes/sneaky.md"
  git -C "$CALLER_PWD" add notes/sneaky.md

  run git -C "$CALLER_PWD" commit -m "should fail"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-obfuscated filenames"* ]]
  [[ "$output" == *"sneaky.md"* ]]
}

@test "pre-commit hook allows obfuscated files" {
  notes setup
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "setup"

  notes obfuscate
  git -C "$CALLER_PWD" add -A

  run git -C "$CALLER_PWD" commit -m "should succeed"
  [ "$status" -eq 0 ]
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
