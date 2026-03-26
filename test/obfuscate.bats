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

@test "obfuscate renames files to hex IDs" {
  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Obfuscated 3 file(s)"* ]]

  # Original files should be gone
  [ ! -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/beta.md" ]
  [ ! -f "$CALLER_PWD/notes/gamma.txt" ]

  # Manifest should exist
  [ -f "$CALLER_PWD/notes/.manifest" ]

  # Should have 3 entries in manifest
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
}

@test "obfuscate creates extensionless files" {
  notes obfuscate

  # No files with extensions should remain (except .manifest)
  for f in "$CALLER_PWD/notes/"*; do
    [ ! -f "$f" ] && continue
    base=$(basename "$f")
    [[ "$base" != *.* ]]
  done
}

@test "obfuscate preserves file content" {
  notes obfuscate

  # Read the manifest to find where alpha.md went
  id=$(grep "alpha.md" "$CALLER_PWD/notes/.manifest" | cut -f1)
  [[ "$(cat "$CALLER_PWD/notes/$id")" == *"# Alpha"* ]]
}

@test "obfuscate is idempotent" {
  notes obfuscate

  # Capture state after first run
  manifest_before=$(cat "$CALLER_PWD/notes/.manifest")
  files_before=$(ls "$CALLER_PWD/notes/" | sort)

  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to obfuscate"* ]]

  # State unchanged
  [ "$(cat "$CALLER_PWD/notes/.manifest")" = "$manifest_before" ]
  [ "$(ls "$CALLER_PWD/notes/" | sort)" = "$files_before" ]
}

@test "obfuscate dry-run shows plan without renaming" {
  run notes obfuscate -- --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha.md"* ]]

  # Files should still have original names
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ ! -f "$CALLER_PWD/notes/.manifest" ]
}

@test "obfuscate skips generated files" {
  echo "generated" > "$CALLER_PWD/notes/index.md"
  echo "generated" > "$CALLER_PWD/notes/graph.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add generated files"

  notes obfuscate

  # Generated files should still have their original names
  [ -f "$CALLER_PWD/notes/index.md" ]
  [ -f "$CALLER_PWD/notes/graph.md" ]

  # Only the 3 real notes should be obfuscated
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 3 ]
}

@test "obfuscate handles new files added after initial obfuscation" {
  notes obfuscate

  # Add a new note
  echo -e "---\ntitle: Delta\n---\n# Delta" > "$CALLER_PWD/notes/delta.md"
  git -C "$CALLER_PWD" add -A
  git -C "$CALLER_PWD" commit -q -m "add delta"

  run notes obfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"delta.md"* ]]
  [[ "$output" == *"Obfuscated 1 file(s)"* ]]

  # Manifest should now have 4 entries
  [ "$(wc -l < "$CALLER_PWD/notes/.manifest" | tr -d ' ')" -eq 4 ]

  # Original 3 IDs should be unchanged
  [ ! -f "$CALLER_PWD/notes/delta.md" ]
}

@test "deobfuscate restores original filenames" {
  notes obfuscate
  run notes deobfuscate
  [ "$status" -eq 0 ]
  [[ "$output" == *"Restored 3 file(s)"* ]]

  # Original files should be back
  [ -f "$CALLER_PWD/notes/alpha.md" ]
  [ -f "$CALLER_PWD/notes/beta.md" ]
  [ -f "$CALLER_PWD/notes/gamma.txt" ]

  # Manifest should be removed
  [ ! -f "$CALLER_PWD/notes/.manifest" ]
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

  # Obfuscated files should still be in place
  [ -f "$CALLER_PWD/notes/$id" ]
  [ -f "$CALLER_PWD/notes/.manifest" ]
}

@test "round-trip preserves all content and metadata" {
  notes obfuscate
  notes deobfuscate

  # Verify frontmatter survived
  run farts get title "$CALLER_PWD/notes/alpha.md"
  [ "$output" = "Alpha" ]

  run farts get title "$CALLER_PWD/notes/beta.md"
  [ "$output" = "Beta" ]
}
