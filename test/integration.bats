#!/usr/bin/env bats
# Integration tests for the encryption workflow: setup → add-user → lock → unlock → status

load test_helper

# Override setup/teardown for GPG isolation
setup() {
  # Short temp path — gpg-agent Unix socket has 104-char limit on macOS
  export TEST_DIR=$(mktemp -d /tmp/notes-test.XXXXXX)

  export TARGET_DIR="$TEST_DIR/repo"
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init -q -b main
  git -C "$TARGET_DIR" config user.email "test@notes.local"
  git -C "$TARGET_DIR" config user.name "notes-test"
  git -C "$TARGET_DIR" config commit.gpgsign false

  export CALLER_PWD="$TARGET_DIR"
  export MISE_CONFIG_ROOT="$REPO_DIR"
  source "$REPO_DIR/lib/common.sh"

  # Isolated GPG home
  export GNUPGHOME="$TEST_DIR/gpg"
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"
}

teardown() {
  gpgconf --homedir "$GNUPGHOME" --kill gpg-agent 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

generate_test_key() {
  local homedir="$1"
  gpg --homedir "$homedir" --batch --passphrase '' --quick-gen-key \
    "test-user <test@notes.local>" default default never 2>/dev/null
  gpg --homedir "$homedir" --batch --with-colons --list-keys 2>/dev/null \
    | awk -F: '/^fpr/{print $10; exit}'
}

# --- add-user ---

@test "add-user adds collaborator via rudi" {
  # Setup first
  "$REPO_DIR/.mise/tasks/setup"

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  [ -n "$fpr" ]

  export usage_gpg_key="$fpr"
  run "$REPO_DIR/.mise/tasks/add-user"
  [ "$status" -eq 0 ]

  # Key file should exist in .git-crypt
  [ -f "$TARGET_DIR/.git-crypt/keys/default/0/$fpr.gpg" ]
}

# --- lock / unlock round-trip ---

@test "lock and unlock round-trip preserves file content" {
  # Setup and add user
  "$REPO_DIR/.mise/tasks/setup"

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  export usage_gpg_key="$fpr"
  "$REPO_DIR/.mise/tasks/add-user"

  # Commit a file in the encrypted path
  mkdir -p "$TARGET_DIR/notes"
  echo "secret content" > "$TARGET_DIR/notes/secret.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add encrypted note"

  # Lock
  run "$REPO_DIR/.mise/tasks/lock"
  [ "$status" -eq 0 ]

  # File should not be readable as plaintext
  ! grep -q "secret content" "$TARGET_DIR/notes/secret.md" 2>/dev/null

  # Unlock
  run "$REPO_DIR/.mise/tasks/unlock"
  [ "$status" -eq 0 ]

  # File should be readable again
  grep -q "secret content" "$TARGET_DIR/notes/secret.md"
}

# --- status ---

@test "status shows encryption info" {
  "$REPO_DIR/.mise/tasks/setup"

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  export usage_gpg_key="$fpr"
  "$REPO_DIR/.mise/tasks/add-user"

  run "$REPO_DIR/.mise/tasks/status"
  [ "$status" -eq 0 ]
  # rudi status should show something meaningful
  [ -n "$output" ]
}

# --- end-to-end ---

@test "full workflow: setup → add-user → commit → lock → unlock → verify" {
  # 1. Setup with default pattern
  run "$REPO_DIR/.mise/tasks/setup"
  [ "$status" -eq 0 ]
  [ -f "$TARGET_DIR/.gitattributes" ]

  # 2. Add a collaborator
  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  export usage_gpg_key="$fpr"
  "$REPO_DIR/.mise/tasks/add-user"
  [ -f "$TARGET_DIR/.git-crypt/keys/default/0/$fpr.gpg" ]

  # 3. Commit encrypted files
  mkdir -p "$TARGET_DIR/notes"
  echo "top secret" > "$TARGET_DIR/notes/classified.md"
  echo "also secret" > "$TARGET_DIR/notes/private.md"
  echo "not encrypted" > "$TARGET_DIR/public.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add files"

  # 4. Lock
  "$REPO_DIR/.mise/tasks/lock"
  ! grep -q "top secret" "$TARGET_DIR/notes/classified.md" 2>/dev/null
  ! grep -q "also secret" "$TARGET_DIR/notes/private.md" 2>/dev/null
  # Public file should be unaffected
  grep -q "not encrypted" "$TARGET_DIR/public.md"

  # 5. Unlock
  "$REPO_DIR/.mise/tasks/unlock"
  grep -q "top secret" "$TARGET_DIR/notes/classified.md"
  grep -q "also secret" "$TARGET_DIR/notes/private.md"

  # 6. Verify the key
  local keyfile="$TEST_DIR/test.pub.asc"
  gpg --homedir "$GNUPGHOME" --batch --armor --export "$fpr" > "$keyfile"
  export usage_key_file="$keyfile"
  run "$REPO_DIR/.mise/tasks/verify"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verified"* ]]
}
