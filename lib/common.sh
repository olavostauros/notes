#!/usr/bin/env bash
# common.sh — shared helpers for notes tasks
#
# This file contains require checks and manifest helpers used by all tasks.
# Specialized functionality lives in separate files:
#   - obfuscate.sh — Layer 1 filesystem rename operations
#   - suppress.sh  — status suppression (assume-unchanged + exclude)
#   - hooks.sh     — git hook installation

# The target repo is always CALLER_PWD (set by shiv shim)
TARGET_DIR="${CALLER_PWD:-.}"

# Where the hook source files live (in the notes repo)
HOOKS_DIR="${MISE_CONFIG_ROOT}/hooks"

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

# ── Manifest helpers ──────────────────────────────────────────
# Manifest format: <id>\t<name>
# All functions take the manifest path as first arg.

# Look up id by name. Prints id or nothing.
manifest_id_for_name() {
  local manifest="$1" name="$2"
  [ ! -f "$manifest" ] && return
  while IFS=$'\t' read -r id entry_name; do
    if [ "$entry_name" = "$name" ]; then
      printf '%s' "$id"
      return
    fi
  done < "$manifest"
}

# Check if an id exists in the manifest.
manifest_has_id() {
  local manifest="$1" id="$2"
  [ -f "$manifest" ] && grep -q "^${id}"$'\t' "$manifest"
}

# Look up name by id. Prints name or nothing.
manifest_name_for_id() {
  local manifest="$1" id="$2"
  [ ! -f "$manifest" ] && return
  grep "^${id}"$'\t' "$manifest" | cut -f2
}
