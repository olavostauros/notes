#!/usr/bin/env bats

load test_helper

# --- Text output ---

@test "status shows encryption state" {
  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Encryption:"
}

@test "status shows not_initialized when no git-crypt" {
  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not_initialized"
}

@test "status shows encryption unlocked after setup" {
  notes setup
  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "unlocked"
}

@test "status shows obfuscation state" {
  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Obfuscation:"
}

@test "status shows obfuscation none when no manifest" {
  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "none"
}

@test "status shows obfuscation state after obfuscate" {
  notes setup
  mkdir -p "$TARGET_DIR/notes"
  echo -e "---\ntitle: Test\n---\n# Test" > "$TARGET_DIR/notes/test-note.md"
  git -C "$TARGET_DIR" add -A
  git -C "$TARGET_DIR" commit -q -m "add note"
  notes obfuscate

  run notes status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "obfuscated"
  echo "$output" | grep -q "1 notes"
}

# --- JSON output ---

@test "status --json outputs valid JSON" {
  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq empty
}

@test "status --json has encryption and obfuscation fields" {
  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.encryption.status'
  echo "$output" | jq -e '.obfuscation.status'
}

@test "status --json shows not_initialized when no git-crypt" {
  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.encryption.status == "not_initialized"'
  echo "$output" | jq -e '.encryption.unlocked == false'
}

@test "status --json shows unlocked after setup" {
  notes setup
  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.encryption.status == "unlocked"'
  echo "$output" | jq -e '.encryption.unlocked == true'
}

@test "status --json shows obfuscation none when no manifest" {
  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.obfuscation.status == "none"'
  echo "$output" | jq -e '.obfuscation.notes == 0'
}

@test "status --json shows note count after obfuscate" {
  notes setup
  mkdir -p "$TARGET_DIR/notes"
  echo -e "---\ntitle: Alpha\n---\n# Alpha" > "$TARGET_DIR/notes/alpha.md"
  echo -e "---\ntitle: Beta\n---\n# Beta" > "$TARGET_DIR/notes/beta.md"
  git -C "$TARGET_DIR" add -A
  git -C "$TARGET_DIR" commit -q -m "add notes"
  notes obfuscate

  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.obfuscation.status == "obfuscated"'
  echo "$output" | jq -e '.obfuscation.notes == 2'
}

@test "status --json shows deobfuscated after deobfuscate" {
  notes setup
  mkdir -p "$TARGET_DIR/notes"
  echo -e "---\ntitle: Test\n---\n# Test" > "$TARGET_DIR/notes/test-note.md"
  git -C "$TARGET_DIR" add -A
  git -C "$TARGET_DIR" commit -q -m "add note"
  notes obfuscate
  notes deobfuscate

  run notes status -- --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.obfuscation.status == "deobfuscated"'
}
