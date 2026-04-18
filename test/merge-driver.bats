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

# ── git-crypt integration (notes#48) ──────────────────────────
#
# Regression: git invokes the merge driver with index content, which for
# git-crypt-tracked files is the encrypted ciphertext (10-byte header
# \0GITCRYPT\0 followed by AEAD-encrypted payload). The driver must decrypt
# before attempting to parse tab-separated entries, or it silently produces
# a 0-byte merged manifest and wipes the mapping for all collaborators.
#
# Symptom observed on den main 2026-04-15 → 2026-04-17: manifest toggled
# between 0 bytes and tiny partial fragments across every merge commit,
# causing agents' `notes stage` to misidentify tracked obfuscated files
# as "new" on every session.

@test "merge driver: encrypted inputs (git-crypt) are decrypted before merge" {
  # Skip if git-crypt isn't installed locally.
  if ! command -v git-crypt >/dev/null; then
    skip "git-crypt not installed"
  fi

  # Set up a real git-crypt'd repo so we have valid encrypted content.
  local repo="$BATS_TEST_TMPDIR/crypt-repo"
  mkdir -p "$repo"
  git -C "$repo" init -q
  ( cd "$repo" && git-crypt init >/dev/null 2>&1 ) || skip "git-crypt init failed"

  # Tell git-crypt to encrypt notes/.manifest
  cat > "$repo/.gitattributes" <<EOT
notes/.manifest filter=git-crypt diff=git-crypt
EOT
  mkdir -p "$repo/notes"

  # Write a plaintext manifest, commit (clean filter encrypts it on write-to-index)
  cat > "$repo/notes/.manifest" <<EOT
aaa00001	alpha.md
bbb00001	beta.md
EOT
  git -C "$repo" add .gitattributes notes/.manifest
  git -C "$repo" -c user.email=t@t -c user.name=t commit -qm "init"

  # Extract the encrypted blob from the index — that's what git hands the merge driver
  local encrypted_anc="$BATS_TEST_TMPDIR/enc_anc"
  local encrypted_ours="$BATS_TEST_TMPDIR/enc_ours"
  local encrypted_theirs="$BATS_TEST_TMPDIR/enc_theirs"

  git -C "$repo" cat-file -p "HEAD:notes/.manifest" > "$encrypted_anc"

  # Verify we really have encrypted content (header check)
  local header
  header=$(dd if="$encrypted_anc" bs=1 skip=1 count=8 2>/dev/null)
  [ "$header" = "GITCRYPT" ] || fail "expected encrypted content but got: $(head -c 20 "$encrypted_anc" | od -An -c)"

  # Create an "ours" variant with one added entry, encrypted the same way
  cat > "$repo/notes/.manifest" <<EOT
aaa00001	alpha.md
bbb00001	beta.md
ccc00001	gamma.md
EOT
  git -C "$repo" add notes/.manifest
  git -C "$repo" -c user.email=t@t -c user.name=t commit -qm "ours"
  git -C "$repo" cat-file -p "HEAD:notes/.manifest" > "$encrypted_ours"

  # Create a "theirs" variant with a different added entry
  cat > "$repo/notes/.manifest" <<EOT
aaa00001	alpha.md
bbb00001	beta.md
ddd00001	delta.md
EOT
  git -C "$repo" add notes/.manifest
  git -C "$repo" -c user.email=t@t -c user.name=t commit -qm "theirs"
  git -C "$repo" cat-file -p "HEAD:notes/.manifest" > "$encrypted_theirs"

  # Run the merge driver from inside the repo (git-crypt needs access to
  # keys). `run` has to execute in the calling shell to set $status/$output,
  # so we cd into the repo here. Tests after this one should only rely on
  # setup()'s absolute-path helpers ($TARGET_DIR, $BATS_TEST_TMPDIR).
  cd "$repo"
  run bash "$DRIVER" "$encrypted_anc" "$encrypted_ours" "$encrypted_theirs"

  # Expect successful merge (no conflict; union of additions)
  [ "$status" -eq 0 ]

  # Result is written back to `ours` — and git will run the clean filter on
  # it before writing to the index, so the driver must output PLAINTEXT.
  local result_size
  result_size=$(wc -c < "$encrypted_ours" | tr -d ' ')
  [ "$result_size" -gt 0 ] || fail "driver wrote empty result — encrypted input not decrypted"

  # All three entries should be present (alpha from ancestor, gamma from ours, delta from theirs)
  grep -qF "alpha.md" "$encrypted_ours" || fail "missing alpha.md: $(cat "$encrypted_ours")"
  grep -qF "beta.md"  "$encrypted_ours" || fail "missing beta.md"
  grep -qF "gamma.md" "$encrypted_ours" || fail "missing gamma.md"
  grep -qF "delta.md" "$encrypted_ours" || fail "missing delta.md"
}

@test "merge driver: plaintext inputs (no git-crypt) still merge correctly" {
  # Ensure the git-crypt detection doesn't break the plaintext path.
  make_manifest "$ANCESTOR" "aaa00001\talpha.md"
  make_manifest "$OURS"     "aaa00001\talpha.md" "bbb00001\tbeta.md"
  make_manifest "$THEIRS"   "aaa00001\talpha.md" "ccc00001\tgamma.md"

  run bash "$DRIVER" "$ANCESTOR" "$OURS" "$THEIRS"
  [ "$status" -eq 0 ]

  grep -qF "alpha.md" "$OURS"
  grep -qF "beta.md"  "$OURS"
  grep -qF "gamma.md" "$OURS"
}

@test "merge driver: fails loudly when git-crypt smudge cannot decrypt" {
  # If git-crypt is locked (or keys are missing), smudge fails. The driver
  # must exit non-zero with a diagnostic rather than silently writing garbage
  # — letting git produce a visible merge conflict that forces investigation.
  if ! command -v git-crypt >/dev/null; then
    skip "git-crypt not installed"
  fi

  # Set up repo A with git-crypt, produce an encrypted blob.
  local repo_a="$BATS_TEST_TMPDIR/repo-a"
  mkdir -p "$repo_a"
  git -C "$repo_a" init -q
  ( cd "$repo_a" && git-crypt init >/dev/null 2>&1 ) || skip "git-crypt init failed"
  cat > "$repo_a/.gitattributes" <<EOT
notes/.manifest filter=git-crypt diff=git-crypt
EOT
  mkdir -p "$repo_a/notes"
  echo "aaa00001	alpha.md" > "$repo_a/notes/.manifest"
  git -C "$repo_a" add .gitattributes notes/.manifest
  git -C "$repo_a" -c user.email=t@t -c user.name=t commit -qm "init"

  # Extract the encrypted blob.
  local encrypted="$BATS_TEST_TMPDIR/enc"
  git -C "$repo_a" cat-file -p "HEAD:notes/.manifest" > "$encrypted"
  # Sanity: it really is encrypted
  local header
  header=$(dd if="$encrypted" bs=1 skip=1 count=8 2>/dev/null)
  [ "$header" = "GITCRYPT" ] || fail "expected encrypted content"

  # Now run the driver from repo B which has no git-crypt keys for repo A.
  local repo_b="$BATS_TEST_TMPDIR/repo-b"
  mkdir -p "$repo_b"
  git -C "$repo_b" init -q
  # No git-crypt init in repo_b — smudge will fail with a key-mismatch error.

  cd "$repo_b"
  # Driver calls normalize() on each of ancestor/ours/theirs; the first call
  # fails at git-crypt smudge and `set -e` aborts the script. We pass the
  # same encrypted blob for all three inputs since only the first will be
  # read before the failure.
  run bash "$DRIVER" "$encrypted" "$encrypted" "$encrypted"

  [ "$status" -ne 0 ]
  [[ "$output" == *"git-crypt smudge failed"* ]]
  [[ "$output" == *"aborting merge"* ]]
}
