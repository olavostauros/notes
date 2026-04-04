#!/usr/bin/env bash
# common.sh — shared helpers for notes tasks

# The target repo is always CALLER_PWD (set by shiv shim)
TARGET_DIR="${CALLER_PWD:-.}"

# Where the hook source files live (in the notes repo)
HOOKS_DIR="${MISE_CONFIG_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/hooks"

# ── Require checks ────────────────────────────────────────────

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
  [ -d "$TARGET_DIR/.git-crypt" ] || [ -d "$TARGET_DIR/.git/git-crypt" ]
}

require_initialized() {
  if ! is_initialized; then
    echo "Error: git-crypt not initialized. Run: notes setup" >&2
    exit 1
  fi
}

# ── Hook installation ─────────────────────────────────────────

# Ensure the pre-commit dispatcher is installed.
# Individual checks live in .git/hooks/pre-commit.d/ as separate scripts.
ensure_hook_dispatcher() {
  local hooks_dir="$TARGET_DIR/.git/hooks"
  local dispatcher="$hooks_dir/pre-commit"

  mkdir -p "$hooks_dir/pre-commit.d"

  # Only install if the dispatcher isn't already in place
  if ! grep -q "pre-commit.d" "$dispatcher" 2>/dev/null; then
    cp "$HOOKS_DIR/dispatcher" "$dispatcher"
    chmod +x "$dispatcher"
  fi
}

# Install the encryption pre-commit check.
install_encryption_hook() {
  ensure_hook_dispatcher
  local target="$TARGET_DIR/.git/hooks/pre-commit.d/encryption"
  cp "$HOOKS_DIR/encryption" "$target"
  chmod +x "$target"
}

# Install the obfuscation pre-commit check.
# Bakes in the notes directory path from the template.
install_obfuscation_hook() {
  local notes_dir="${1:-notes}"
  ensure_hook_dispatcher
  local target="$TARGET_DIR/.git/hooks/pre-commit.d/obfuscation"
  sed "s|__NOTES_DIR__|$notes_dir|g" "$HOOKS_DIR/obfuscation.template" > "$target"
  chmod +x "$target"
}
