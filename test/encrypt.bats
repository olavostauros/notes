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
  source "$REPO_DIR/lib/common.sh"
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
  export CALLER_PWD="$TARGET_DIR"
  run "$REPO_DIR/.mise/tasks/encrypt/setup"
  [ "$status" -eq 0 ]

  [ -f "$TARGET_DIR/.gitattributes" ]
  grep -q "notes/\*\*" "$TARGET_DIR/.gitattributes"
  grep -q "git-crypt" "$TARGET_DIR/.gitattributes"
}

@test "setup is idempotent" {
  export CALLER_PWD="$TARGET_DIR"
  "$REPO_DIR/.mise/tasks/encrypt/setup"

  run "$REPO_DIR/.mise/tasks/encrypt/setup"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already initialized"* ]]
}

@test "setup with custom patterns writes them to .gitattributes" {
  export CALLER_PWD="$TARGET_DIR"
  export usage_pattern="agents/*/Zettels/**
notes/private/**"
  run "$REPO_DIR/.mise/tasks/encrypt/setup"
  [ "$status" -eq 0 ]

  grep -q "agents/\*/Zettels/\*\*" "$TARGET_DIR/.gitattributes"
  grep -q "notes/private/\*\*" "$TARGET_DIR/.gitattributes"
}

@test "setup installs pre-commit hook" {
  export CALLER_PWD="$TARGET_DIR"
  "$REPO_DIR/.mise/tasks/encrypt/setup"

  [ -x "$TARGET_DIR/.git/hooks/pre-commit" ]
  grep -q "git-crypt" "$TARGET_DIR/.git/hooks/pre-commit"
}

@test "setup without keys does not create COLLABORATORS" {
  export CALLER_PWD="$TARGET_DIR"
  "$REPO_DIR/.mise/tasks/encrypt/setup"

  # .git-crypt/keys/default/0/ only exists after first add-gpg-user
  [ ! -d "$TARGET_DIR/.git-crypt/keys/default/0" ]
}
