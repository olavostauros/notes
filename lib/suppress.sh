#!/usr/bin/env bash
# suppress.sh — Status suppression for deobfuscated working trees
#
# After deobfuscation, the working tree has readable names but the index
# has obfuscated names. Two sources of noise in `git status`:
#   1. Obfuscated IDs appear as "deleted" (file missing from disk)
#   2. Readable names appear as "untracked" (not in the index)
#
# We suppress both:
#   - `assume-unchanged` on obfuscated paths → hides "deleted" noise
#   - `.git/info/exclude` entries for readable names → hides "untracked" noise
#
# Because exclude also blocks `git add`, users stage notes via `notes stage`
# (which uses `git add -f` to bypass exclude). See notes#39.

# Managed block markers in .git/info/exclude
EXCLUDE_BEGIN="# BEGIN notes-obfuscation"
EXCLUDE_END="# END notes-obfuscation"

# Add readable names to .git/info/exclude.
# Usage: add_exclude_entries <abs_notes_dir> [id...]
#   Without IDs: adds all manifest entries (full mode)
#   With IDs: adds only the readable names for the specified IDs (scoped mode)
add_exclude_entries() {
  local abs_notes_dir="${1:?usage: add_exclude_entries <abs_notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  local repo_root
  repo_root=$(git -C "$abs_notes_dir" rev-parse --show-toplevel 2>/dev/null) || return
  local notes_dir="${abs_notes_dir#"$repo_root"/}"
  local exclude_file="$repo_root/.git/info/exclude"

  # Ensure the info directory exists
  mkdir -p "$(dirname "$exclude_file")"

  # Collect entries to add
  local entries=()
  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      local relpath
      relpath=$(manifest_name_for_id "$manifest" "$id")
      [ -n "$relpath" ] && entries+=("$notes_dir/$relpath")
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      entries+=("$notes_dir/$relpath")
    done < "$manifest"
  fi

  [ ${#entries[@]} -eq 0 ] && return

  # Read existing managed entries (if any)
  local existing=()
  if [ -f "$exclude_file" ]; then
    local in_block=false
    while IFS= read -r line; do
      if [ "$line" = "$EXCLUDE_BEGIN" ]; then
        in_block=true
        continue
      fi
      if [ "$line" = "$EXCLUDE_END" ]; then
        in_block=false
        continue
      fi
      if $in_block && [ -n "$line" ]; then
        existing+=("$line")
      fi
    done < "$exclude_file"
  fi

  # Merge: add new entries that aren't already present
  local merged=()
  for e in ${existing[@]+"${existing[@]}"}; do
    merged+=("$e")
  done
  for entry in "${entries[@]}"; do
    local found=false
    for e in ${existing[@]+"${existing[@]}"}; do
      if [ "$e" = "$entry" ]; then
        found=true
        break
      fi
    done
    if ! $found; then
      merged+=("$entry")
    fi
  done

  # Rewrite the exclude file: preserve non-managed content, replace managed block
  _rewrite_exclude_block "$exclude_file" "${merged[@]}"
}

# Remove readable names from .git/info/exclude.
# Usage: remove_exclude_entries <abs_notes_dir> [id...]
#   Without IDs: removes the entire managed block (full mode)
#   With IDs: removes only the readable names for the specified IDs (scoped mode)
remove_exclude_entries() {
  local abs_notes_dir="${1:?usage: remove_exclude_entries <abs_notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  local repo_root
  repo_root=$(git -C "$abs_notes_dir" rev-parse --show-toplevel 2>/dev/null) || return
  local notes_dir="${abs_notes_dir#"$repo_root"/}"
  local exclude_file="$repo_root/.git/info/exclude"

  [ ! -f "$exclude_file" ] && return

  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    # Scoped: collect paths to remove, keep the rest
    local to_remove=()
    for id in "${scoped_ids[@]}"; do
      local relpath
      relpath=$(manifest_name_for_id "$manifest" "$id")
      [ -n "$relpath" ] && to_remove+=("$notes_dir/$relpath")
    done

    # Read existing managed entries, filter out the ones to remove
    local remaining=()
    local in_block=false
    while IFS= read -r line; do
      if [ "$line" = "$EXCLUDE_BEGIN" ]; then
        in_block=true
        continue
      fi
      if [ "$line" = "$EXCLUDE_END" ]; then
        in_block=false
        continue
      fi
      if $in_block && [ -n "$line" ]; then
        local should_remove=false
        for r in "${to_remove[@]}"; do
          if [ "$line" = "$r" ]; then
            should_remove=true
            break
          fi
        done
        if ! $should_remove; then
          remaining+=("$line")
        fi
      fi
    done < "$exclude_file"

    _rewrite_exclude_block "$exclude_file" ${remaining[@]+"${remaining[@]}"}
  else
    # Full mode: remove the entire managed block
    _rewrite_exclude_block "$exclude_file"
  fi
}

# Rewrite .git/info/exclude: preserve non-managed content, replace managed block.
# Usage: _rewrite_exclude_block <exclude_file> [entries...]
#   With entries: writes a BEGIN/END block containing them
#   Without entries: removes the managed block entirely
_rewrite_exclude_block() {
  local exclude_file="$1"
  shift
  local entries=("$@")

  local tmp
  tmp=$(mktemp) || return

  # Copy non-managed content
  if [ -f "$exclude_file" ]; then
    local in_block=false
    while IFS= read -r line; do
      if [ "$line" = "$EXCLUDE_BEGIN" ]; then
        in_block=true
        continue
      fi
      if [ "$line" = "$EXCLUDE_END" ]; then
        in_block=false
        continue
      fi
      if ! $in_block; then
        printf '%s\n' "$line" >> "$tmp"
      fi
    done < "$exclude_file"
  fi

  # Append managed block if there are entries
  if [ ${#entries[@]} -gt 0 ] && [ -n "${entries[0]}" ]; then
    printf '%s\n' "$EXCLUDE_BEGIN" >> "$tmp"
    for entry in "${entries[@]}"; do
      printf '%s\n' "$entry" >> "$tmp"
    done
    printf '%s\n' "$EXCLUDE_END" >> "$tmp"
  fi

  mv -f "$tmp" "$exclude_file"
}

# Set assume-unchanged on obfuscated paths + add exclude entries for readable names.
# Call after deobfuscating.
# Usage: set_status_suppression <abs_notes_dir> [id...]
#   Without IDs: sets flags for all entries in the manifest (full mode)
#   With IDs: sets flags for the specified IDs only (scoped mode)
set_status_suppression() {
  local abs_notes_dir="${1:?usage: set_status_suppression <abs_notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  local repo_root
  repo_root=$(git -C "$abs_notes_dir" rev-parse --show-toplevel 2>/dev/null) || return
  local notes_dir="${abs_notes_dir#"$repo_root"/}"

  # Set assume-unchanged flags
  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      git -C "$repo_root" update-index --assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      git -C "$repo_root" update-index --assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done < "$manifest"
  fi

  # Add exclude entries for readable names
  add_exclude_entries "$abs_notes_dir" "${scoped_ids[@]}"
}

# Clear assume-unchanged flags + remove exclude entries for readable names.
# Call before obfuscating.
# Usage: clear_status_suppression <abs_notes_dir> [id...]
#   Without IDs: clears all flags (full mode)
#   With IDs: clears only the specified IDs (scoped mode)
clear_status_suppression() {
  local abs_notes_dir="${1:?usage: clear_status_suppression <abs_notes_dir>}"
  shift
  local scoped_ids=("$@")
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  local repo_root
  repo_root=$(git -C "$abs_notes_dir" rev-parse --show-toplevel 2>/dev/null) || return
  local notes_dir="${abs_notes_dir#"$repo_root"/}"

  # Clear assume-unchanged flags
  if [ ${#scoped_ids[@]} -gt 0 ] && [ -n "${scoped_ids[0]}" ]; then
    for id in "${scoped_ids[@]}"; do
      git -C "$repo_root" update-index --no-assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done
  else
    while IFS=$'\t' read -r id relpath; do
      [ -z "$id" ] && continue
      git -C "$repo_root" update-index --no-assume-unchanged "$notes_dir/$id" 2>/dev/null || true
    done < "$manifest"
  fi

  # Remove exclude entries for readable names
  remove_exclude_entries "$abs_notes_dir" "${scoped_ids[@]}"
}
