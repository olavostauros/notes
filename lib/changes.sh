#!/usr/bin/env bash
# changes.sh — Detect changed notes by comparing deobfuscated files against HEAD
#
# In the deobfuscated state, readable files on disk don't match what git tracks
# (obfuscated IDs in the index). This library compares readable content against
# committed content to detect modifications, additions, and deletions.

# Detect changed notes relative to HEAD.
# Outputs one line per change: "<status>\t<readable_name>"
# Status values: modified, new, deleted
# Usage: detect_changes <abs_notes_dir>
detect_changes() {
  local abs_notes_dir="${1:?usage: detect_changes <abs_notes_dir>}"
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  resolve_notes_dir "$abs_notes_dir" || return
  local repo_root="$RESOLVED_REPO_ROOT"
  local notes_dir="$RESOLVED_NOTES_DIR"

  while IFS=$'\t' read -r id relpath; do
    [ -z "$id" ] && continue

    local readable_file="$abs_notes_dir/$relpath"
    local git_path="$notes_dir/$id"

    if [ -f "$readable_file" ]; then
      # File exists on disk — check if it's new or modified
      local head_hash
      head_hash=$(git -C "$repo_root" rev-parse "HEAD:$git_path" 2>/dev/null) || {
        # Not in HEAD — it's a new note
        printf 'new\t%s\n' "$relpath"
        continue
      }

      # Hash the readable file through git's clean filter (handles encryption).
      # --path tells git which .gitattributes filters to apply.
      local disk_hash
      disk_hash=$(git -C "$repo_root" hash-object --path="$git_path" "$readable_file" 2>/dev/null) || continue
      if [ "$head_hash" != "$disk_hash" ]; then
        printf 'modified\t%s\n' "$relpath"
      fi
    else
      # Readable name not on disk — check if obfuscated form exists
      # (if neither exists, the note was deleted)
      if [ ! -f "$abs_notes_dir/$id" ]; then
        # Check it was actually committed (not just a stale manifest entry)
        if git -C "$repo_root" show "HEAD:$git_path" &>/dev/null; then
          printf 'deleted\t%s\n' "$relpath"
        fi
      fi
      # If obfuscated form exists on disk, the file isn't deobfuscated — skip
    fi
  done < "$manifest"

  # Scan for new files not yet in the manifest
  while IFS= read -r f; do
    [ ! -f "$f" ] && continue
    local relpath="${f#"$abs_notes_dir"/}"
    [[ "$relpath" == ".manifest" ]] && continue

    # Skip obfuscated IDs (8-char hex filenames that are in the manifest)
    local base
    base=$(basename "$relpath")
    manifest_has_id "$manifest" "$base" && continue

    # Skip files already in the manifest (by readable name)
    local existing_id
    existing_id=$(manifest_id_for_name "$manifest" "$relpath" || true)
    [ -n "$existing_id" ] && continue

    # This is a genuinely new file
    printf 'new\t%s\n' "$relpath"
  done < <(find "$abs_notes_dir" -type f | sort)
}

# Show diffs for changed notes.
# Usage: show_diffs <abs_notes_dir> [file...]
#   Without files: diffs all changed notes
#   With files: diffs only the specified notes (readable names, relative to notes dir)
show_diffs() {
  local abs_notes_dir="${1:?usage: show_diffs <abs_notes_dir>}"
  shift
  local filter_files=("$@")
  local manifest="$abs_notes_dir/.manifest"
  [ ! -f "$manifest" ] && return

  resolve_notes_dir "$abs_notes_dir" || return
  local repo_root="$RESOLVED_REPO_ROOT"
  local notes_dir="$RESOLVED_NOTES_DIR"

  local changes
  changes=$(detect_changes "$abs_notes_dir") || return
  [ -z "$changes" ] && return

  while IFS=$'\t' read -r status relpath; do
    # Apply file filter if specified
    if [ ${#filter_files[@]} -gt 0 ] && [ -n "${filter_files[0]}" ]; then
      local match=false
      for f in "${filter_files[@]}"; do
        if [ "$f" = "$relpath" ]; then
          match=true
          break
        fi
      done
      $match || continue
    fi

    local readable_file="$abs_notes_dir/$relpath"
    local git_path="$notes_dir/$id"
    local id
    id=$(manifest_id_for_name "$manifest" "$relpath")
    git_path="$notes_dir/$id"

    case "$status" in
      modified)
        echo "=== $relpath (modified) ==="
        # Use cat-file --filters to get decrypted content (handles git-crypt)
        local tmp
        tmp=$(mktemp) || continue
        git -C "$repo_root" cat-file --filters "HEAD:$git_path" > "$tmp" 2>/dev/null
        diff -u --label "a/$relpath" --label "b/$relpath" "$tmp" "$readable_file" || true
        rm -f "$tmp"
        echo ""
        ;;
      new)
        echo "=== $relpath (new) ==="
        diff -u --label /dev/null --label "b/$relpath" /dev/null "$readable_file" || true
        echo ""
        ;;
      deleted)
        echo "=== $relpath (deleted) ==="
        local tmp
        tmp=$(mktemp) || continue
        git -C "$repo_root" cat-file --filters "HEAD:$git_path" > "$tmp" 2>/dev/null
        diff -u --label "a/$relpath" --label /dev/null "$tmp" /dev/null || true
        rm -f "$tmp"
        echo ""
        ;;
    esac
  done <<< "$changes"
}
