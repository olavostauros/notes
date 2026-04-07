#!/usr/bin/env bash
# common.sh — shared helpers for notes tasks

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

# ── Layer 1: Filesystem + Manifest operations ────────────────
# Pure renames + manifest updates. No git staging, no suppression.

# Rename readable files to obfuscated IDs.
# Outputs "<relpath>\t<id>" per renamed file (for callers to stage).
# Usage: rename_to_obfuscated <notes_dir> [file...]
#   Without files: scans notes_dir for all non-obfuscated files.
#   With files: only processes the listed files (relative to notes_dir).
rename_to_obfuscated() {
  local notes_dir="$1"
  shift
  local scoped_files=("$@")
  local manifest="$notes_dir/.manifest"

  local to_rename=() to_restore=()

  if [ ${#scoped_files[@]} -gt 0 ] && [ -n "${scoped_files[0]}" ]; then
    for relpath in "${scoped_files[@]}"; do
      [[ "$relpath" == ".manifest" ]] && continue
      [ ! -f "$notes_dir/$relpath" ] && continue

      local base
      base=$(basename "$relpath")
      if manifest_has_id "$manifest" "$base"; then
        continue  # already obfuscated
      fi

      local existing_id
      existing_id=$(manifest_id_for_name "$manifest" "$relpath" || true)
      if [ -n "$existing_id" ]; then
        to_restore+=("$relpath")
      else
        to_rename+=("$relpath")
      fi
    done
  else
    while IFS= read -r f; do
      [ ! -f "$f" ] && continue
      local relpath="${f#"$notes_dir"/}"
      [[ "$relpath" == ".manifest" ]] && continue

      local base
      base=$(basename "$f")
      if manifest_has_id "$manifest" "$base"; then
        continue
      fi

      local existing_id
      existing_id=$(manifest_id_for_name "$manifest" "$relpath" || true)
      if [ -n "$existing_id" ]; then
        to_restore+=("$relpath")
      else
        to_rename+=("$relpath")
      fi
    done < <(find "$notes_dir" -type f | sort)
  fi

  if [ ${#to_rename[@]} -eq 0 ] && [ ${#to_restore[@]} -eq 0 ]; then
    return 1  # nothing to do
  fi

  # Track new manifest entries
  local new_entries
  new_entries=$(mktemp)

  # Restore files to their known IDs
  for relpath in ${to_restore[@]+"${to_restore[@]}"}; do
    local id
    id=$(manifest_id_for_name "$manifest" "$relpath" || true)
    mv "$notes_dir/$relpath" "$notes_dir/$id"
    printf '%s\t%s\n' "$relpath" "$id"
  done

  # Generate IDs and rename new files
  for relpath in ${to_rename[@]+"${to_rename[@]}"}; do
    local id
    id=$(openssl rand -hex 4)
    while manifest_has_id "$manifest" "$id" || \
          grep -q "^${id}"$'\t' "$new_entries" 2>/dev/null || \
          [ -f "$notes_dir/$id" ]; do
      id=$(openssl rand -hex 4)
    done

    printf '%s\t%s\n' "$id" "$relpath" >> "$new_entries"
    mv "$notes_dir/$relpath" "$notes_dir/$id"
    printf '%s\t%s\n' "$relpath" "$id"
  done

  # Clean up empty directories after flattening
  find "$notes_dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true

  # Update manifest: merge existing + new entries, sorted by name.
  # An entry is live if either its obfuscated id or readable name is on disk.
  local merged
  merged=$(mktemp)

  if [ -f "$manifest" ]; then
    while IFS=$'\t' read -r id name; do
      [ -z "$id" ] && continue
      if [ -f "$notes_dir/$id" ] || [ -f "$notes_dir/$name" ]; then
        printf '%s\t%s\n' "$id" "$name"
      fi
    done < "$manifest" > "$merged"
  fi

  cat "$new_entries" >> "$merged"
  sort -t$'\t' -k2 "$merged" > "$manifest"
  rm -f "$merged" "$new_entries"
}

# Rename obfuscated IDs back to readable names.
# Outputs "<id>\t<relpath>" per renamed file.
# Usage: rename_to_readable <notes_dir> [id...]
#   Without ids: deobfuscates all files listed in the manifest.
#   With ids: only deobfuscates the specified IDs.
rename_to_readable() {
  local notes_dir="$1"
  shift
  local scoped_ids=("$@")
  local manifest="$notes_dir/.manifest"
  local count=0

  [ ! -f "$manifest" ] && return 1

  _deobfuscate_one() {
    local id="$1"
    local relpath
    relpath=$(manifest_name_for_id "$manifest" "$id")
    [ -z "$relpath" ] && return
    [ ! -f "$notes_dir/$id" ] && return

    local target_dir
    target_dir=$(dirname "$notes_dir/$relpath")
    [ ! -d "$target_dir" ] && mkdir -p "$target_dir"

    mv "$notes_dir/$id" "$notes_dir/$relpath"
    printf '%s\t%s\n' "$id" "$relpath"
    ((count++)) || true
  }

  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      _deobfuscate_one "$id"
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      _deobfuscate_one "$id"
    done < "$manifest"
  fi

  [ "$count" -eq 0 ] && return 1
  return 0
}

# ── Status suppression (assume-unchanged) ────────────────────

# After deobfuscation, the working tree has readable names but the index
# has obfuscated names. The obfuscated files appear as "deleted" in git
# status. We suppress this noise with assume-unchanged on the obfuscated
# paths so git doesn't report them as missing.
#
# Readable names will show as "untracked" — this is intentional. They're
# the files users edit, and they need to be stageable via `git add`.
# Using .git/info/exclude would hide them from status but also block
# `git add`, breaking the normal workflow.

# Set assume-unchanged on obfuscated paths. Call after deobfuscating.
# Usage: set_status_suppression <notes_dir> [id...]
#   Without IDs: sets flags for all entries in the manifest (full mode)
#   With IDs: sets flags for the specified IDs only (scoped mode)
set_status_suppression() {
  local notes_dir="${1:?usage: set_status_suppression <notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$TARGET_DIR/$notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      git -C "$TARGET_DIR" update-index --assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      git -C "$TARGET_DIR" update-index --assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done < "$manifest"
  fi
}

# Clear assume-unchanged flags. Call before obfuscating.
# Usage: clear_status_suppression <notes_dir> [id...]
#   Without IDs: clears all flags (full mode)
#   With IDs: clears only the specified IDs (scoped mode)
clear_status_suppression() {
  local notes_dir="${1:?usage: clear_status_suppression <notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$TARGET_DIR/$notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      git -C "$TARGET_DIR" update-index --no-assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      git -C "$TARGET_DIR" update-index --no-assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done < "$manifest"
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
