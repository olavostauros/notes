#!/usr/bin/env bats

load test_helper

setup() {
  export REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export NOTES_DIR="$BATS_TEST_TMPDIR/notes"
  mkdir -p "$NOTES_DIR"
}

@test "generates README.md from note with frontmatter" {
  cat > "$NOTES_DIR/test-note.md" <<'EOF'
---
title: Test Note
tags: [testing, example]
related: []
created: 2026-03-14
updated: 2026-03-14
---

# Test Note

This is a test note.
EOF

  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/README.md" ]
  grep -q "Test Note" "$NOTES_DIR/README.md"
  grep -q "testing" "$NOTES_DIR/README.md"
  grep -q "example" "$NOTES_DIR/README.md"
}

@test "notes without frontmatter listed in unconverted section" {
  cat > "$NOTES_DIR/no-frontmatter.md" <<'EOF'
# Just a plain note

No YAML frontmatter here.
EOF

  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  grep -q "no-frontmatter.md" "$NOTES_DIR/README.md"
  grep -q "Without Frontmatter" "$NOTES_DIR/README.md"
}

@test "wikilinks generate backlinks in graph.md" {
  cat > "$NOTES_DIR/note-a.md" <<'EOF'
---
title: Note A
tags: [test]
related: []
created: 2026-03-14
updated: 2026-03-14
---

# Note A

This links to [[note-b]].
EOF

  cat > "$NOTES_DIR/note-b.md" <<'EOF'
---
title: Note B
tags: [test]
related: []
created: 2026-03-14
updated: 2026-03-14
---

# Note B

Standalone note.
EOF

  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/graph.md" ]
  # note-a should have outgoing link to note-b
  grep -q "note-a.*note-b" "$NOTES_DIR/graph.md"
  # note-b should have backlink from note-a
  grep -q "note-b.*note-a" "$NOTES_DIR/graph.md"
}

@test "empty directory generates valid index" {
  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  [ -f "$NOTES_DIR/README.md" ]
  [ -f "$NOTES_DIR/graph.md" ]
  grep -q "No tags yet" "$NOTES_DIR/README.md"
}

@test "skips README.md and graph.md when scanning" {
  cat > "$NOTES_DIR/README.md" <<'EOF'
# Old README
EOF
  cat > "$NOTES_DIR/graph.md" <<'EOF'
# Old Graph
EOF
  cat > "$NOTES_DIR/real-note.md" <<'EOF'
---
title: Real Note
tags: [test]
related: []
created: 2026-03-14
updated: 2026-03-14
---

# Real Note
EOF

  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  # README should be regenerated with Real Note, not contain old content
  grep -q "Real Note" "$NOTES_DIR/README.md"
  ! grep -q "Old README" "$NOTES_DIR/README.md"
}

@test "explicit relations appear in graph" {
  cat > "$NOTES_DIR/note-x.md" <<'EOF'
---
title: Note X
tags: [test]
related: [note-y]
created: 2026-03-14
updated: 2026-03-14
---

# Note X
EOF

  cat > "$NOTES_DIR/note-y.md" <<'EOF'
---
title: Note Y
tags: [test]
related: []
created: 2026-03-14
updated: 2026-03-14
---

# Note Y
EOF

  run python3 "$REPO_DIR/lib/notes_index.py" "$NOTES_DIR"
  [ "$status" -eq 0 ]

  grep -q "Explicit Relations" "$NOTES_DIR/graph.md"
  grep -q "note-x.*note-y" "$NOTES_DIR/graph.md"
}
