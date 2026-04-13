#!/usr/bin/env bats

# Tests for git operations (pull, rebase, merge) with obfuscated notes.
# Each test creates a "remote" bare repo and a "local" clone to simulate
# real multi-user / multi-machine workflows.

load test_helper

# Override default setup — we need a remote + local pair, not a single repo.
setup() {
  source "$MISE_CONFIG_ROOT/lib/common.sh"

  # Create a bare "remote" repo
  export REMOTE="$BATS_TEST_TMPDIR/remote.git"
  git init -q --bare -b main "$REMOTE"

  # Create the "origin" working copy (simulates another machine / agent)
  export ORIGIN="$BATS_TEST_TMPDIR/origin"
  git clone -q "$REMOTE" "$ORIGIN"
  git -C "$ORIGIN" config user.email "test@test.com"
  git -C "$ORIGIN" config user.name "Test"

  # Create initial notes, obfuscate, commit, push
  mkdir -p "$ORIGIN/notes"
  echo -e "---\ntitle: Alpha\n---\n# Alpha" > "$ORIGIN/notes/alpha.md"
  echo -e "---\ntitle: Beta\n---\n# Beta" > "$ORIGIN/notes/beta.md"
  git -C "$ORIGIN" add -A
  git -C "$ORIGIN" commit -q -m "initial notes"

  export CALLER_PWD="$ORIGIN"
  notes obfuscate
  git -C "$ORIGIN" commit -q -m "obfuscate"

  # Install hooks on origin too (both sides need them)
  notes install-hooks
  notes deobfuscate

  git -C "$ORIGIN" push -q

  # Clone to "local" (simulates your working copy)
  export LOCAL="$BATS_TEST_TMPDIR/local"
  git clone -q "$REMOTE" "$LOCAL"
  git -C "$LOCAL" config user.email "test@test.com"
  git -C "$LOCAL" config user.name "Test"

  # Deobfuscate + install hooks (including merge driver) on local
  export CALLER_PWD="$LOCAL"
  notes deobfuscate
  notes install-hooks
}

# ── Pull ──────────────────────────────────────────────────────

@test "pull: new note from remote appears deobfuscated locally" {
  # Origin adds a new note (hooks auto-obfuscate on commit)
  echo -e "---\ntitle: Gamma\n---\n# Gamma" > "$ORIGIN/notes/gamma.md"
  CALLER_PWD="$ORIGIN" notes stage gamma.md
  git -C "$ORIGIN" commit -q -m "add gamma"
  git -C "$ORIGIN" push -q

  # Local pulls — post-merge hook deobfuscates
  git -C "$LOCAL" pull -q

  [ -f "$LOCAL/notes/gamma.md" ]
  [[ "$(cat "$LOCAL/notes/gamma.md")" == *"# Gamma"* ]]
  grep -q "gamma.md" "$LOCAL/notes/.manifest"
}

@test "pull: remote edit to existing note is visible locally" {
  # Origin edits alpha (readable on disk, hooks handle obfuscation)
  echo "Updated content" >> "$ORIGIN/notes/alpha.md"
  CALLER_PWD="$ORIGIN" notes stage alpha.md
  git -C "$ORIGIN" commit -q -m "edit alpha"
  git -C "$ORIGIN" push -q

  # Local: re-obfuscate before pull so readable files don't conflict
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .
  git -C "$LOCAL" pull -q

  # Deobfuscate to see the updated content
  CALLER_PWD="$LOCAL" notes deobfuscate
  [ -f "$LOCAL/notes/alpha.md" ]
  [[ "$(cat "$LOCAL/notes/alpha.md")" == *"Updated content"* ]]
}

@test "pull: new note doesn't conflict with unrelated local readable files" {
  # Local has deobfuscated alpha.md and beta.md (untracked)
  [ -f "$LOCAL/notes/alpha.md" ]
  [ -f "$LOCAL/notes/beta.md" ]

  # Origin adds a completely new note and pushes
  echo -e "---\ntitle: Delta\n---\n# Delta" > "$ORIGIN/notes/delta.md"
  CALLER_PWD="$ORIGIN" notes stage delta.md
  git -C "$ORIGIN" commit -q -m "add delta"
  git -C "$ORIGIN" push -q

  # Pull succeeds — new obfuscated ID doesn't clash with untracked readable names
  run git -C "$LOCAL" pull -q
  [ "$status" -eq 0 ]

  # Post-merge hook deobfuscates the new note
  [ -f "$LOCAL/notes/delta.md" ]
  # Existing notes still present
  [ -f "$LOCAL/notes/alpha.md" ]
}

@test "pull: remote edit to existing note works even with readable files on disk" {
  # Origin edits alpha and pushes (hooks auto-obfuscate)
  echo "origin change" >> "$ORIGIN/notes/alpha.md"
  CALLER_PWD="$ORIGIN" notes stage alpha.md
  git -C "$ORIGIN" commit -q -m "edit alpha"
  git -C "$ORIGIN" push -q

  # Local has deobfuscated alpha.md on disk (untracked).
  # Pull works because git only tracks the obfuscated IDs — readable
  # names are untracked and don't conflict with obfuscated path changes.
  [ -f "$LOCAL/notes/alpha.md" ]
  run git -C "$LOCAL" pull -q
  [ "$status" -eq 0 ]

  # Post-merge hook deobfuscates — local alpha.md now has the update.
  # But the old untracked alpha.md is still on disk... the post-merge
  # hook overwrites it because deobfuscate uses mv from the obfuscated ID.
  [[ "$(cat "$LOCAL/notes/alpha.md")" == *"origin change"* ]]
}

# ── Merge ─────────────────────────────────────────────────────

@test "merge: concurrent note additions auto-merge via manifest driver" {
  # With the manifest merge driver installed, concurrent additions to
  # .manifest are union-merged automatically.
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .

  # Branch: add a note
  git -C "$LOCAL" checkout -q -b feature
  echo -e "---\ntitle: Feature Note\n---\n# Feature" > "$LOCAL/notes/feature.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add feature note"

  # Main: add a different note
  git -C "$LOCAL" checkout -q main
  echo -e "---\ntitle: Main Note\n---\n# Main" > "$LOCAL/notes/main-note.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add main note"

  # Merge succeeds — driver union-merges the manifest
  run git -C "$LOCAL" merge feature --no-edit
  [ "$status" -eq 0 ]

  # Manifest has all entries (alpha, beta, feature, main-note)
  [ "$(wc -l < "$LOCAL/notes/.manifest" | tr -d ' ')" -eq 4 ]
  grep -q "feature.md" "$LOCAL/notes/.manifest"
  grep -q "main-note.md" "$LOCAL/notes/.manifest"
}

@test "merge: single-branch addition merges cleanly" {
  # When only one branch adds notes and the other doesn't touch
  # the manifest, merge succeeds.
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .

  # Branch: add a note
  git -C "$LOCAL" checkout -q -b feature
  echo -e "---\ntitle: Feature\n---\n# Feature" > "$LOCAL/notes/feature.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add feature"

  # Main: add a non-notes file (no manifest change)
  git -C "$LOCAL" checkout -q main
  echo "readme" > "$LOCAL/README.md"
  git -C "$LOCAL" add README.md
  git -C "$LOCAL" commit -q --no-verify -m "add readme"

  # Merge succeeds
  run git -C "$LOCAL" merge feature -q --no-edit
  [ "$status" -eq 0 ]

  CALLER_PWD="$LOCAL" notes deobfuscate
  [ -f "$LOCAL/notes/feature.md" ]
}

@test "merge: conflicting edits to same obfuscated file" {
  alpha_id=$(grep "alpha.md" "$LOCAL/notes/.manifest" | cut -f1)

  # Re-obfuscate for clean branch operations
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .

  # Create a branch, edit alpha's obfuscated file directly
  git -C "$LOCAL" checkout -q -b branch-a
  echo "branch-a edit" >> "$LOCAL/notes/$alpha_id"
  git -C "$LOCAL" add "notes/$alpha_id"
  git -C "$LOCAL" commit -q --no-verify -m "branch-a edits alpha"

  # Back to main, edit alpha differently
  git -C "$LOCAL" checkout -q main
  echo "main edit" >> "$LOCAL/notes/$alpha_id"
  git -C "$LOCAL" add "notes/$alpha_id"
  git -C "$LOCAL" commit -q --no-verify -m "main edits alpha"

  # Merge should conflict
  run git -C "$LOCAL" merge branch-a --no-edit
  [ "$status" -ne 0 ]
  [[ "$(cat "$LOCAL/notes/$alpha_id")" == *"<<<<<<"* ]]
}

# ── Rebase ────────────────────────────────────────────────────

@test "rebase: works when only feature branch adds notes" {
  # Rebase succeeds when main doesn't touch the manifest
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .

  # Create a branch with a new note
  git -C "$LOCAL" checkout -q -b feature
  echo -e "---\ntitle: Feature\n---\n# Feature" > "$LOCAL/notes/feature.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add feature"

  # Main: non-notes change
  git -C "$LOCAL" checkout -q main
  echo "readme" > "$LOCAL/README.md"
  git -C "$LOCAL" add README.md
  git -C "$LOCAL" commit -q --no-verify -m "add readme"

  # Rebase feature onto main
  git -C "$LOCAL" checkout -q feature
  run git -C "$LOCAL" rebase main
  [ "$status" -eq 0 ]

  CALLER_PWD="$LOCAL" notes deobfuscate
  [ -f "$LOCAL/notes/feature.md" ]
}

@test "rebase: concurrent note additions auto-merge via manifest driver" {
  # With the merge driver, concurrent manifest changes are union-merged.
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" checkout -- .

  # Feature branch: add a note
  git -C "$LOCAL" checkout -q -b feature
  echo -e "---\ntitle: Feature\n---\n# Feature" > "$LOCAL/notes/feature.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add feature"

  # Main: add a different note
  git -C "$LOCAL" checkout -q main
  echo -e "---\ntitle: Other\n---\n# Other" > "$LOCAL/notes/other.md"
  CALLER_PWD="$LOCAL" notes obfuscate
  git -C "$LOCAL" commit -q --no-verify -m "add other"

  # Rebase succeeds — driver union-merges the manifest
  git -C "$LOCAL" checkout -q feature
  run git -C "$LOCAL" rebase main
  [ "$status" -eq 0 ]

  # Manifest has all entries
  grep -q "feature.md" "$LOCAL/notes/.manifest"
  grep -q "other.md" "$LOCAL/notes/.manifest"
}
