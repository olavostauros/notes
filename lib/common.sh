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

# Ensure a hook dispatcher is installed for the given hook type.
# Usage: ensure_hook_dispatcher <pre-commit|post-commit|post-merge>
ensure_hook_dispatcher() {
  local hook_type="${1:?usage: ensure_hook_dispatcher <pre-commit|post-commit|post-merge>}"
  local hooks_dir="$TARGET_DIR/.git/hooks"
  local dispatcher="$hooks_dir/$hook_type"

  mkdir -p "$hooks_dir/${hook_type}.d"

  # Only install if the dispatcher isn't already in place
  if ! grep -q "${hook_type}.d" "$dispatcher" 2>/dev/null; then
    cp "$HOOKS_DIR/dispatcher" "$dispatcher"
    chmod +x "$dispatcher"
  fi
}

# Install the encryption pre-commit check.
install_encryption_hook() {
  ensure_hook_dispatcher pre-commit
  local target="$TARGET_DIR/.git/hooks/pre-commit.d/encryption"
  cp "$HOOKS_DIR/encryption" "$target"
  chmod +x "$target"
}

# Install the obfuscation pre-commit check.
# Bakes in the notes directory path from the template.
install_obfuscation_hook() {
  local notes_dir="${1:-notes}"
  ensure_hook_dispatcher pre-commit
  local target="$TARGET_DIR/.git/hooks/pre-commit.d/obfuscation"
  sed "s|__NOTES_DIR__|$notes_dir|g" "$HOOKS_DIR/obfuscation.template" > "$target"
  chmod +x "$target"
}

# Install the post-commit deobfuscation hook.
# After a commit obfuscates filenames, this restores them for the working tree.
install_deobfuscation_hook() {
  local notes_dir="${1:-notes}"
  local template="$HOOKS_DIR/post-commit-deobfuscate.template"

  # Install for post-commit (deobfuscate after committing)
  ensure_hook_dispatcher post-commit
  local target="$TARGET_DIR/.git/hooks/post-commit.d/deobfuscation"
  sed "s|__NOTES_DIR__|$notes_dir|g" "$template" > "$target"
  chmod +x "$target"

  # Install for post-merge (deobfuscate after pulling)
  ensure_hook_dispatcher post-merge
  local merge_target="$TARGET_DIR/.git/hooks/post-merge.d/deobfuscation"
  sed "s|__NOTES_DIR__|$notes_dir|g" "$template" > "$merge_target"
  chmod +x "$merge_target"
}
