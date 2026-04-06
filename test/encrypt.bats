#!/usr/bin/env bats

load test_helper

@test "is_initialized returns false on fresh repo" {
  run is_initialized
  [ "$status" -ne 0 ]
}

@test "is_initialized returns true after git crypt init" {
  git -C "$TARGET_DIR" crypt init
  run is_initialized
  [ "$status" -eq 0 ]
}

@test "require_git fails on non-git directory" {
  export CALLER_PWD="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$CALLER_PWD"
  source "$MISE_CONFIG_ROOT/lib/common.sh"
  run require_git
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
}

@test "require_initialized fails when not initialized" {
  run require_initialized
  [ "$status" -ne 0 ]
  [[ "$output" == *"not initialized"* ]]
}

@test "setup writes .gitattributes with default pattern" {
  run notes setup
  [ "$status" -eq 0 ]

  [ -f "$TARGET_DIR/.gitattributes" ]
  grep -q "notes/\*\*" "$TARGET_DIR/.gitattributes"
  grep -q "git-crypt" "$TARGET_DIR/.gitattributes"
}

@test "setup is idempotent" {
  notes setup

  run notes setup
  [ "$status" -eq 0 ]
  [[ "$output" == *"git-crypt already initialized — updating auxiliary files..."* ]]
}

@test "setup with custom patterns writes them to .gitattributes" {
  run notes setup -- --pattern "agents/*/Zettels/**" --pattern "notes/private/**"
  [ "$status" -eq 0 ]

  grep -q "agents/\*/Zettels/\*\*" "$TARGET_DIR/.gitattributes"
  grep -q "notes/private/\*\*" "$TARGET_DIR/.gitattributes"
}

@test "setup installs pre-commit hooks" {
  notes setup

  # Dispatcher
  [ -x "$TARGET_DIR/.git/hooks/pre-commit" ]
  grep -q "Generic hook dispatcher" "$TARGET_DIR/.git/hooks/pre-commit"

  # Individual hooks
  [ -x "$TARGET_DIR/.git/hooks/pre-commit.d/encryption" ]
  grep -q "git-crypt" "$TARGET_DIR/.git/hooks/pre-commit.d/encryption"
  [ -x "$TARGET_DIR/.git/hooks/pre-commit.d/obfuscation" ]
  grep -q "manifest" "$TARGET_DIR/.git/hooks/pre-commit.d/obfuscation"
}

@test "setup without keys does not add gpg users" {
  notes setup

  # .git-crypt/keys/default/0/ only exists after first add-gpg-user
  [ ! -d "$TARGET_DIR/.git-crypt/keys/default/0" ]
}

# --- verify tests ---
# These use a temporary GPG keyring with a test key

generate_test_key() {
  local homedir="$1"
  gpg --homedir "$homedir" --batch --passphrase '' --quick-gen-key \
    "test-user <test@example.com>" default default never 2>/dev/null
  gpg --homedir "$homedir" --batch --with-colons --list-keys 2>/dev/null \
    | awk -F: '/^fpr/{print $10; exit}'
}

@test "verify succeeds with matching key and fingerprint" {
  local keyhome="$BATS_TEST_TMPDIR/gpghome"
  mkdir -p "$keyhome"
  chmod 700 "$keyhome"

  local fpr
  fpr=$(generate_test_key "$keyhome")
  [ -n "$fpr" ]

  local keyfile="$BATS_TEST_TMPDIR/test.pub.asc"
  gpg --homedir "$keyhome" --batch --armor --export "$fpr" > "$keyfile"

  run notes verify -- --gpg-key "$fpr" --key-file "$keyfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verified"* ]]
  [[ "$output" == *"matches the claimed fingerprint"* ]]
}

@test "verify fails with mismatched fingerprint" {
  local keyhome="$BATS_TEST_TMPDIR/gpghome"
  mkdir -p "$keyhome"
  chmod 700 "$keyhome"

  local fpr
  fpr=$(generate_test_key "$keyhome")

  local keyfile="$BATS_TEST_TMPDIR/test.pub.asc"
  gpg --homedir "$keyhome" --batch --armor --export "$fpr" > "$keyfile"

  run notes verify -- --gpg-key "0000000000000000000000000000000000000000" --key-file "$keyfile"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISMATCH"* ]]
}

@test "verify reads from stdin with --key-file -" {
  local keyhome="$BATS_TEST_TMPDIR/gpghome"
  mkdir -p "$keyhome"
  chmod 700 "$keyhome"

  local fpr
  fpr=$(generate_test_key "$keyhome")

  run bash -c "gpg --homedir '$keyhome' --batch --armor --export '$fpr' | notes verify -- --gpg-key '$fpr' --key-file -"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verified"* ]]
}
