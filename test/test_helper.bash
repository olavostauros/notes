# Tests must be run via `mise run test` (or `notes test`)
if [ -z "${MISE_CONFIG_ROOT:-}" ]; then
  echo "MISE_CONFIG_ROOT not set — run tests via: mise run test" >&2
  exit 1
fi

# Source lib files at file-load time, not inside setup(). Most .bats files in
# this suite override setup() to set their own CALLER_PWD/fixtures, which
# shadows the helper's setup() and silently drops the lib sources. Sourcing
# at top level makes the helper functions available in every test body
# regardless of which setup wins.
source "$MISE_CONFIG_ROOT/lib/common.sh"
source "$MISE_CONFIG_ROOT/lib/obfuscate.sh"
source "$MISE_CONFIG_ROOT/lib/suppress.sh"
source "$MISE_CONFIG_ROOT/lib/hooks.sh"

# notes() wrapper — calls tasks via mise, just like real usage
# Exported so subshells (e.g. bash -c pipes) can use it too.
notes() {
  if [ -z "${CALLER_PWD:-}" ]; then
    echo "CALLER_PWD not set" >&2
    return 1
  fi
  cd "$MISE_CONFIG_ROOT" && CALLER_PWD="$CALLER_PWD" mise run -q "$@"
}
export -f notes

# rudi() wrapper — calls rudi with CALLER_PWD set
rudi() {
  if [ -z "${CALLER_PWD:-}" ]; then
    echo "CALLER_PWD not set" >&2
    return 1
  fi
  CALLER_PWD="$CALLER_PWD" command rudi "$@"
}
export -f rudi

setup() {
  export TARGET_DIR="$BATS_TEST_TMPDIR/test-repo"
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init -q
  export CALLER_PWD="$TARGET_DIR"
}
