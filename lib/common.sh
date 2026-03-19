#!/usr/bin/env bash
# common.sh — shared helpers for notes tasks

# The target repo is always CALLER_PWD (set by shiv shim)
TARGET_DIR="${CALLER_PWD:-.}"

require_git() {
  if ! git -C "$TARGET_DIR" rev-parse --git-dir &>/dev/null; then
    echo "Error: not a git repository: $TARGET_DIR" >&2
    exit 1
  fi
}

require_rudi() {
  if ! command -v rudi &>/dev/null; then
    echo "Error: rudi not found. Install it: shiv install rudi" >&2
    exit 1
  fi
}

is_initialized() {
  # .git-crypt/ exists after add-gpg-user (committed keys)
  # .git/git-crypt/ exists after git crypt init (local state)
  [ -d "$TARGET_DIR/.git-crypt" ] || [ -d "$TARGET_DIR/.git/git-crypt" ]
}

require_initialized() {
  if ! is_initialized; then
    echo "Error: git-crypt not initialized. Run: notes setup" >&2
    exit 1
  fi
}
