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

  export NOTES_CALLER_PWD="$TARGET_DIR"
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
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  [ -n "$fpr" ]

  run notes add-user -- --gpg-key "$fpr"
  [ "$status" -eq 0 ]

  # Key file should exist in .git-crypt
  [ -f "$TARGET_DIR/.git-crypt/keys/default/0/$fpr.gpg" ]
}

# --- lock / unlock round-trip ---

@test "lock and unlock round-trip preserves file content" {
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  # Commit a file in the encrypted path
  mkdir -p "$TARGET_DIR/notes"
  echo "secret content" > "$TARGET_DIR/notes/secret.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add encrypted note"

  # Lock
  run notes lock --yes
  [ "$status" -eq 0 ]

  # File should not be readable as plaintext
  ! grep -q "secret content" "$TARGET_DIR/notes/secret.md" 2>/dev/null

  # Unlock
  run notes unlock
  [ "$status" -eq 0 ]

  # File should be readable again
  grep -q "secret content" "$TARGET_DIR/notes/secret.md"
}

@test "lock refuses without confirmation before staging or obfuscating" {
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  mkdir -p "$TARGET_DIR/notes"
  echo "plain note" > "$TARGET_DIR/notes/plain.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q --no-verify -m "Add encrypted note"

  run without_confirmation "$TEST_DIR/missing-tty" notes lock

  [ "$status" -eq 2 ]
  [[ "$output" == *"confirmation required"* ]]
  [[ "$output" == *"Re-run with --yes"* ]]
  [ -f "$TARGET_DIR/notes/plain.md" ]
  grep -q "plain note" "$TARGET_DIR/notes/plain.md"
  ! grep -q "plain.md" "$TARGET_DIR/notes/.manifest"
  [ -z "$(git -C "$TARGET_DIR" diff --cached --name-only)" ]
}

# --- status ---

@test "status shows encryption info" {
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  run notes status
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

# --- end-to-end ---

@test "full workflow: setup → add-user → commit → lock → unlock → verify" {
  # 1. Setup with default pattern
  run notes setup --yes
  [ "$status" -eq 0 ]
  [ -f "$TARGET_DIR/.gitattributes" ]

  # 2. Add a collaborator
  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"
  [ -f "$TARGET_DIR/.git-crypt/keys/default/0/$fpr.gpg" ]

  # 3. Commit encrypted files
  mkdir -p "$TARGET_DIR/notes"
  echo "top secret" > "$TARGET_DIR/notes/classified.md"
  echo "also secret" > "$TARGET_DIR/notes/private.md"
  echo "not encrypted" > "$TARGET_DIR/public.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add files"

  # 4. Lock
  notes lock --yes
  ! grep -q "top secret" "$TARGET_DIR/notes/classified.md" 2>/dev/null
  ! grep -q "also secret" "$TARGET_DIR/notes/private.md" 2>/dev/null
  # Public file should be unaffected
  grep -q "not encrypted" "$TARGET_DIR/public.md"

  # 5. Unlock
  notes unlock
  grep -q "top secret" "$TARGET_DIR/notes/classified.md"
  grep -q "also secret" "$TARGET_DIR/notes/private.md"

  # 6. Verify the key
  local keyfile="$TEST_DIR/test.pub.asc"
  gpg --homedir "$GNUPGHOME" --batch --armor --export "$fpr" > "$keyfile"
  run notes verify -- --gpg-key "$fpr" --key-file "$keyfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Verified"* ]]
}

# --- lock/unlock + obfuscation chaining ---

setup_encrypted_repo_with_obfuscation() {
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  mkdir -p "$TARGET_DIR/notes"
  echo "alpha content" > "$TARGET_DIR/notes/alpha.md"
  echo "beta content" > "$TARGET_DIR/notes/beta.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add notes"

  # Obfuscate to create the manifest
  notes obfuscate
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Obfuscate"

  # Deobfuscate so we're in working state
  notes deobfuscate
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q --no-verify -m "Deobfuscate for working"
}

# TODO: lock tests skip — deobfuscated working tree is "dirty" to git-crypt lock.
# Needs rudi --force support or a clean-status obfuscation design.
# See notes#31, BULLETIN.md design thread.
@test "lock obfuscates filenames before locking" {
  skip "git-crypt lock rejects deobfuscated working tree (needs rudi --force)"
  setup_encrypted_repo_with_obfuscation

  # Files should be deobfuscated before lock
  [ -f "$TARGET_DIR/notes/alpha.md" ]
  [ -f "$TARGET_DIR/notes/beta.md" ]

  notes lock --yes

  # Files should be obfuscated (hex IDs, not readable names)
  [ ! -f "$TARGET_DIR/notes/alpha.md" ]
  [ ! -f "$TARGET_DIR/notes/beta.md" ]

  # Manifest should still exist (also encrypted, but file present)
  [ -f "$TARGET_DIR/notes/.manifest" ]
}

@test "unlock deobfuscates filenames after unlocking" {
  skip "git-crypt lock rejects deobfuscated working tree (needs rudi --force)"
  setup_encrypted_repo_with_obfuscation

  notes lock --yes
  # Files are obfuscated + encrypted
  [ ! -f "$TARGET_DIR/notes/alpha.md" ]

  notes unlock

  # Files should be back to readable names
  [ -f "$TARGET_DIR/notes/alpha.md" ]
  [ -f "$TARGET_DIR/notes/beta.md" ]
  grep -q "alpha content" "$TARGET_DIR/notes/alpha.md"
  grep -q "beta content" "$TARGET_DIR/notes/beta.md"
}

@test "lock → unlock round-trip preserves content with obfuscation" {
  skip "git-crypt lock rejects deobfuscated working tree (needs rudi --force)"
  setup_encrypted_repo_with_obfuscation

  notes lock --yes
  notes unlock

  grep -q "alpha content" "$TARGET_DIR/notes/alpha.md"
  grep -q "beta content" "$TARGET_DIR/notes/beta.md"
}

@test "unlock without manifest does not attempt deobfuscation" {
  # Plain encrypted repo, no obfuscation
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  mkdir -p "$TARGET_DIR/notes"
  echo "plain note" > "$TARGET_DIR/notes/plain.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add note"

  notes lock --yes
  run notes unlock
  [ "$status" -eq 0 ]

  # File should be readable with original name
  [ -f "$TARGET_DIR/notes/plain.md" ]
  grep -q "plain note" "$TARGET_DIR/notes/plain.md"
}

@test "lock obfuscates when setup-created manifest exists" {
  notes setup --yes

  local fpr
  fpr=$(generate_test_key "$GNUPGHOME")
  notes add-user -- --gpg-key "$fpr"

  mkdir -p "$TARGET_DIR/notes"
  echo "plain note" > "$TARGET_DIR/notes/plain.md"
  git -C "$TARGET_DIR" add .
  git -C "$TARGET_DIR" commit -q -m "Add note"

  # Capture the manifest entry while unlocked; lock encrypts .manifest too.
  local id
  id=$(awk '$2 == "plain.md" { print $1 }' "$TARGET_DIR/notes/.manifest")
  [ -n "$id" ]

  run notes lock --yes
  [ "$status" -eq 0 ]

  # setup creates .manifest, so lock should keep the committed obfuscated shape.
  [ ! -f "$TARGET_DIR/notes/plain.md" ]
  [ -f "$TARGET_DIR/notes/$id" ]
}
