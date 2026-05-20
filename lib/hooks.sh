#!/usr/bin/env bash
# hooks.sh — Git hook installation helpers

HOOKS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_REPO_DIR="$(cd "$HOOKS_LIB_DIR/.." && pwd)"

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

# Install the manifest merge driver.
# Configures git to use our custom merge driver for .manifest files.
install_manifest_merge_driver() {
  local notes_dir="${1:-notes}"
  local driver_path="$HOOKS_REPO_DIR/lib/manifest-merge-driver.sh"
  local gitattributes="$TARGET_DIR/.gitattributes"

  # Register the merge driver in git config
  git -C "$TARGET_DIR" config merge.manifest.name "Union merge driver for notes manifest"
  git -C "$TARGET_DIR" config merge.manifest.driver "bash \"$driver_path\" %O %A %B"

  # Add .gitattributes entry if not already present
  local pattern="$notes_dir/.manifest merge=manifest"
  if ! grep -qF "$pattern" "$gitattributes" 2>/dev/null; then
    echo "$pattern" >> "$gitattributes"
  fi
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
