#!/usr/bin/env bats

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$NOTES_CALLER_PWD/notes"
}

save_parse_output() {
  parse_json="$BATS_TEST_TMPDIR/parse-output.json"
  printf '%s\n' "$output" > "$parse_json"
}

@test "parse outputs frontmatter/body components for a plain Markdown note" {
  cat > "$NOTES_CALLER_PWD/notes/plain.md" <<'EOF'
# Plain Note

Visible body.
EOF

  run notes parse notes/plain.md
  [ "$status" -eq 0 ]

  save_parse_output
  JSON_PATH="$parse_json" python3 <<'PY'
import json
import os
from pathlib import Path

with Path(os.environ["JSON_PATH"]).open(encoding="utf-8") as handle:
    data = json.load(handle)

assert data["frontmatter"] == {}
assert data["frontmatter_present"] is False
assert data["body"] == "# Plain Note\n\nVisible body.\n"
assert data["diagnostics"] == []
assert set(data) == {"path", "frontmatter", "frontmatter_present", "body", "diagnostics"}
PY
}

@test "parse splits frontmatter from the visible body" {
  cat > "$NOTES_CALLER_PWD/notes/frontmatter.md" <<'EOF'
---
title: Frontmatter Note
tags:
  - testing
  - parser
---
# Frontmatter Note

Visible body.
EOF

  run notes parse frontmatter
  [ "$status" -eq 0 ]

  save_parse_output
  JSON_PATH="$parse_json" python3 <<'PY'
import json
import os
from pathlib import Path

with Path(os.environ["JSON_PATH"]).open(encoding="utf-8") as handle:
    data = json.load(handle)

assert data["frontmatter_present"] is True
assert data["frontmatter"]["title"] == "Frontmatter Note"
assert data["frontmatter"]["tags"] == ["testing", "parser"]
assert data["body"].startswith("# Frontmatter Note")
assert data["diagnostics"] == []
PY
}

@test "parse preserves HTML comments as ordinary body text" {
  cat > "$NOTES_CALLER_PWD/notes/comments.md" <<'EOF'
---
title: Comment Note
---
# Comment Note

Visible body.

<!-- Any future comment-based convention stays in the body for this PR. -->
EOF

  run notes parse comments
  [ "$status" -eq 0 ]

  save_parse_output
  JSON_PATH="$parse_json" python3 <<'PY'
import json
import os
from pathlib import Path

with Path(os.environ["JSON_PATH"]).open(encoding="utf-8") as handle:
    data = json.load(handle)

assert "future comment-based convention" in data["body"]
assert data["diagnostics"] == []
assert set(data) == {"path", "frontmatter", "frontmatter_present", "body", "diagnostics"}
PY
}

@test "parse treats malformed frontmatter delimiters as body text" {
  cat > "$NOTES_CALLER_PWD/notes/malformed.md" <<'EOF'
---
title: Missing End
# This is all still body text.
EOF

  run notes parse malformed
  [ "$status" -eq 0 ]

  save_parse_output
  JSON_PATH="$parse_json" python3 <<'PY'
import json
import os
from pathlib import Path

with Path(os.environ["JSON_PATH"]).open(encoding="utf-8") as handle:
    data = json.load(handle)

assert data["frontmatter_present"] is False
assert data["frontmatter"] == {}
assert data["body"].startswith("---\ntitle: Missing End")
assert data["diagnostics"] == []
PY
}

@test "parse reports missing notes" {
  run notes parse missing
  [ "$status" -ne 0 ]
  [[ "$output" == *"note not found: missing"* ]]
}
