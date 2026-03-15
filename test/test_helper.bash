REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  export TARGET_DIR="$BATS_TEST_TMPDIR/test-repo"
  mkdir -p "$TARGET_DIR"
  git -C "$TARGET_DIR" init -q
  export CALLER_PWD="$TARGET_DIR"
  source "$REPO_DIR/lib/common.sh"
}
