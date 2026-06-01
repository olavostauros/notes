#!/usr/bin/env bats

# Tests for readable note diffs across refs and PR refs.

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$NOTES_CALLER_PWD/notes"
  git -C "$NOTES_CALLER_PWD" init -q
  git -C "$NOTES_CALLER_PWD" config user.name "Test"
  git -C "$NOTES_CALLER_PWD" config user.email "test@test.com"

  echo "# Alpha" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Beta" > "$NOTES_CALLER_PWD/notes/beta.md"
  rename_to_obfuscated "$NOTES_CALLER_PWD/notes" > /dev/null
  git -C "$NOTES_CALLER_PWD" add -A
  git -C "$NOTES_CALLER_PWD" commit -q -m "initial"
  git -C "$NOTES_CALLER_PWD" branch -M main
}

commit_readable_update() {
  local message="$1"
  rename_to_obfuscated "$NOTES_CALLER_PWD/notes" > /dev/null
  git -C "$NOTES_CALLER_PWD" add -A
  git -C "$NOTES_CALLER_PWD" commit -q -m "$message"
}

@test "notes diff with refs shows readable paths and content" {
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Alpha v2" > "$NOTES_CALLER_PWD/notes/alpha.md"
  echo "# Gamma" > "$NOTES_CALLER_PWD/notes/gamma.md"
  commit_readable_update "update notes"

  run notes diff HEAD~1 HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/notes/alpha.md b/notes/alpha.md"* ]]
  [[ "$output" == *"-# Alpha"* ]]
  [[ "$output" == *"+# Alpha v2"* ]]
  [[ "$output" == *"diff --git a/notes/gamma.md b/notes/gamma.md"* ]]
  [[ "$output" == *"+# Gamma"* ]]
  [[ "$output" != *".manifest"* ]]
}

@test "notes diff parses range syntax" {
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Beta v2" > "$NOTES_CALLER_PWD/notes/beta.md"
  commit_readable_update "edit beta"

  run notes diff HEAD~1..HEAD
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/notes/beta.md b/notes/beta.md"* ]]
  [[ "$output" == *"+# Beta v2"* ]]
}

@test "notes diff triple-dot uses merge-base" {
  git -C "$NOTES_CALLER_PWD" checkout -q -b feature
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Alpha feature" > "$NOTES_CALLER_PWD/notes/alpha.md"
  commit_readable_update "edit alpha on feature"

  git -C "$NOTES_CALLER_PWD" checkout -q main
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Beta main" > "$NOTES_CALLER_PWD/notes/beta.md"
  commit_readable_update "edit beta on main"

  run notes diff main...feature
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/notes/alpha.md b/notes/alpha.md"* ]]
  [[ "$output" == *"+# Alpha feature"* ]]
  [[ "$output" != *"beta.md"* ]]
}

@test "notes diff --out writes readable review artifacts" {
  local out_dir
  out_dir="$BATS_TEST_TMPDIR/readable-review"

  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Alpha v2" > "$NOTES_CALLER_PWD/notes/alpha.md"
  commit_readable_update "edit alpha"

  run notes diff --out "$out_dir" HEAD~1 HEAD
  [ "$status" -eq 0 ]
  [ -f "$out_dir/base/notes/alpha.md" ]
  [ -f "$out_dir/head/notes/alpha.md" ]
  [ -f "$out_dir/readable.patch" ]
  grep -q "# Alpha" "$out_dir/base/notes/alpha.md"
  grep -q "# Alpha v2" "$out_dir/head/notes/alpha.md"
  grep -q "diff --git a/notes/alpha.md b/notes/alpha.md" "$out_dir/readable.patch"
  [[ "$output" == *"Wrote readable patch: $out_dir/readable.patch"* ]]
}

@test "notes diff without refs shows working-tree readable diff" {
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Alpha local" > "$NOTES_CALLER_PWD/notes/alpha.md"

  run notes diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"=== alpha.md (modified) ==="* ]]
  [[ "$output" == *"-# Alpha"* ]]
  [[ "$output" == *"+# Alpha local"* ]]
}

@test "notes diff --pr fetches PR refs without checking them out" {
  local origin fake_gh
  origin="$BATS_TEST_TMPDIR/origin.git"
  git init --bare -q "$origin"
  git -C "$NOTES_CALLER_PWD" remote add origin "$origin"
  git -C "$NOTES_CALLER_PWD" push -q origin main:refs/heads/main

  git -C "$NOTES_CALLER_PWD" checkout -q -b pr-branch
  rename_to_readable "$NOTES_CALLER_PWD/notes" > /dev/null
  echo "# Alpha from PR" > "$NOTES_CALLER_PWD/notes/alpha.md"
  commit_readable_update "edit alpha on pr"
  git -C "$NOTES_CALLER_PWD" push -q origin HEAD:refs/pull/1/head
  git -C "$NOTES_CALLER_PWD" checkout -q main

  fake_gh="$BATS_TEST_TMPDIR/gh"
  cat > "$fake_gh" <<'SH'
#!/usr/bin/env bash
printf 'main\n'
SH
  chmod +x "$fake_gh"
  export GH="$fake_gh"

  run notes diff --pr 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"diff --git a/notes/alpha.md b/notes/alpha.md"* ]]
  [[ "$output" == *"+# Alpha from PR"* ]]
  [ "$(git -C "$NOTES_CALLER_PWD" branch --show-current)" = "main" ]
  [ -z "$(git -C "$NOTES_CALLER_PWD" for-each-ref refs/notes-diff)" ]
}
