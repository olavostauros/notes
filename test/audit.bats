#!/usr/bin/env bats

load test_helper

setup() {
  export NOTES_CALLER_PWD="$BATS_TEST_TMPDIR"
  mkdir -p "$NOTES_CALLER_PWD/notes"
}

# Build a small fixture corpus with known link patterns.
#
#   alpha.md   → [[beta]] [[gamma]]                          (outbound: 2)
#   beta.md    → [[alpha]] [[gamma]]                          (outbound: 2)
#   gamma.md   → [[alpha]]                                    (outbound: 1)
#   delta.md   → no links                                     (outbound: 0)
#   epsilon.md → [[alpha]] [[doesnt-exist]] [[KnickKnackLabs/repo]]
#                                                             (outbound: 1
#                                                              real + 1 broken,
#                                                              external excluded)
#
# Expected inbound counts:
#   alpha   ← beta, gamma, epsilon          = 3
#   beta    ← alpha                          = 1
#   gamma   ← alpha, beta                    = 2
#   delta                                    = 0
#   epsilon                                  = 0
#
# Expected outbound counts (excluding the external [[KnickKnackLabs/repo]]):
#   alpha   = 2 (beta + gamma)
#   beta    = 2 (alpha + gamma)
#   gamma   = 1 (alpha)
#   delta   = 0
#   epsilon = 2 (alpha + doesnt-exist)
seed_corpus() {
  cat > "$NOTES_CALLER_PWD/notes/alpha.md" <<'EOF'
---
title: Alpha
---
See [[beta]] and [[gamma]].
EOF
  cat > "$NOTES_CALLER_PWD/notes/beta.md" <<'EOF'
---
title: Beta
---
Refers to [[alpha]] and [[gamma]].
EOF
  cat > "$NOTES_CALLER_PWD/notes/gamma.md" <<'EOF'
---
title: Gamma
---
Refers to [[alpha]] only.
EOF
  cat > "$NOTES_CALLER_PWD/notes/delta.md" <<'EOF'
---
title: Delta
---
No links here.
EOF
  cat > "$NOTES_CALLER_PWD/notes/epsilon.md" <<'EOF'
---
title: Epsilon
---
Has [[alpha]], a broken [[doesnt-exist]], and an external [[KnickKnackLabs/repo]].
EOF
}

@test "audit reports top inbound and outbound counts on the seed corpus" {
  seed_corpus

  run notes audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scanned 5 note(s)"* ]]
  # alpha is the most-linked-to (3 inbound); gamma is second (2 inbound).
  [[ "$output" == *"Top 10 by inbound links:"* ]]
  echo "$output" | grep -E "^  alpha .* inbound:.*3" >/dev/null
  echo "$output" | grep -E "^  gamma .* inbound:.*2" >/dev/null
  # outbound: alpha (2), beta (2), epsilon (2), gamma (1), delta (0).
  [[ "$output" == *"Top 10 by outbound links:"* ]]
  echo "$output" | grep -E "^  alpha .* outbound:.*2" >/dev/null
}

@test "audit reports broken targets but excludes Org/repo-shaped externals" {
  seed_corpus

  run notes audit
  [ "$status" -eq 0 ]
  # epsilon has one real broken target.
  [[ "$output" == *"Broken wikilink targets (1):"* ]]
  [[ "$output" == *"epsilon"* ]]
  [[ "$output" == *"[[doesnt-exist]]"* ]]
  # Any target containing "/" (GitHub-style Org/repo) is external by
  # structure and must NOT show up as broken.
  [[ "$output" != *"KnickKnackLabs/repo"* ]]
}

@test "audit --json emits per-note counts and broken_targets" {
  seed_corpus

  run notes audit -- --json
  [ "$status" -eq 0 ]

  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
notes = data['notes']

# Every fixture note is represented (zero-link islands included).
expected = {'alpha', 'beta', 'gamma', 'delta', 'epsilon'}
assert set(notes.keys()) == expected, f'unexpected keys: {set(notes.keys())}'

# Counts match the fixture's expected graph.
assert notes['alpha']['inbound'] == 3,    notes['alpha']
assert notes['alpha']['outbound'] == 2,   notes['alpha']
assert notes['beta']['inbound'] == 1,     notes['beta']
assert notes['beta']['outbound'] == 2,    notes['beta']
assert notes['gamma']['inbound'] == 2,    notes['gamma']
assert notes['gamma']['outbound'] == 1,   notes['gamma']
assert notes['delta']['inbound'] == 0,    notes['delta']
assert notes['delta']['outbound'] == 0,   notes['delta']
assert notes['epsilon']['inbound'] == 0,  notes['epsilon']
assert notes['epsilon']['outbound'] == 2, notes['epsilon']

# epsilon is the only note with a broken target, and the external
# KnickKnackLabs/repo reference must be filtered out.
assert notes['epsilon']['broken_targets'] == ['doesnt-exist'], notes['epsilon']
assert notes['alpha']['broken_targets'] == []
"
}

@test "audit --top limits the human-readable lists" {
  seed_corpus

  run notes audit -- --top 2
  [ "$status" -eq 0 ]
  # Top 2 by inbound: alpha (3), gamma (2). beta (1) must not appear in
  # the inbound section; check by counting rows between the headers.
  echo "$output" | python3 -c "
import sys
lines = sys.stdin.read().splitlines()
i = lines.index('Top 2 by inbound links:')
# Capture rows until the next blank line.
rows = []
for line in lines[i+1:]:
    if not line.strip():
        break
    rows.append(line)
assert len(rows) == 2, f'expected 2 rows, got {len(rows)}: {rows}'
assert any('alpha' in r for r in rows)
assert any('gamma' in r for r in rows)
assert not any(r.lstrip().startswith('beta ') for r in rows)
"
}

@test "audit ignores wikilinks inside fenced code blocks" {
  cat > "$NOTES_CALLER_PWD/notes/code-example.md" <<'EOF'
---
title: Code example
---
This note shows wikilink syntax in an example:

```
The wikilink syntax is [[target-name]].
```

But it does not actually link to anywhere.
EOF
  # Also add an empty target to make broken-target detection sane.
  cat > "$NOTES_CALLER_PWD/notes/real-target.md" <<'EOF'
---
title: Real
---
Some content.
EOF

  run notes audit -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# The wikilink inside the code fence must not count as outbound.
assert data['notes']['code-example']['outbound'] == 0, data['notes']['code-example']
# And it must not be reported as broken either.
assert data['notes']['code-example']['broken_targets'] == [], data['notes']['code-example']
"
}

@test "audit handles aliased wikilink syntax [[target|display]]" {
  cat > "$NOTES_CALLER_PWD/notes/aliased.md" <<'EOF'
---
title: Aliased
---
This links to [[target|the target]] using the display alias.
EOF
  cat > "$NOTES_CALLER_PWD/notes/target.md" <<'EOF'
---
title: Target
---
Real target.
EOF

  run notes audit -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['notes']['target']['inbound'] == 1, data['notes']['target']
assert data['notes']['aliased']['outbound'] == 1, data['notes']['aliased']
assert data['notes']['aliased']['broken_targets'] == []
"
}

@test "audit ignores empty, unclosed, and nested-bracket wikilink shapes" {
  cat > "$NOTES_CALLER_PWD/notes/malformed.md" <<'EOF'
---
title: Malformed
---
Empty target: [[]].
Unclosed: [[no-close
Nested: [[a[b]c]]
EOF
  cat > "$NOTES_CALLER_PWD/notes/real-target.md" <<'EOF'
---
title: Real
---
Bare content.
EOF

  run notes audit -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Each malformed shape produces zero outbound and zero broken targets.
assert data['notes']['malformed']['outbound'] == 0, data['notes']['malformed']
assert data['notes']['malformed']['broken_targets'] == [], data['notes']['malformed']
"
}

@test "audit ignores wikilinks inside YAML frontmatter" {
  cat > "$NOTES_CALLER_PWD/notes/described.md" <<'EOF'
---
title: Described
description: "See [[some-other-note]] for context."
---
Body has [[real-target]] only.
EOF
  cat > "$NOTES_CALLER_PWD/notes/real-target.md" <<'EOF'
---
title: Real
---
Content.
EOF

  run notes audit -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Frontmatter wikilink must not count as outbound or broken.
# Body wikilink to real-target is the only one that counts.
assert data['notes']['described']['outbound'] == 1, data['notes']['described']
assert data['notes']['described']['broken_targets'] == [], data['notes']['described']
assert data['notes']['real-target']['inbound'] == 1, data['notes']['real-target']
"
}

@test "audit attributes [[target|alias#anchor]] to target" {
  cat > "$NOTES_CALLER_PWD/notes/src.md" <<'EOF'
---
title: Src
---
Link with alias and anchor: [[target|see this#section]].
EOF
  cat > "$NOTES_CALLER_PWD/notes/target.md" <<'EOF'
---
title: Target
---
Real.
EOF

  run notes audit -- --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
# Aliased + anchor: capture group is target only, anchor on the alias
# side never reaches the link_target_stem normalizer.
assert data['notes']['target']['inbound'] == 1, data['notes']['target']
assert data['notes']['src']['outbound'] == 1, data['notes']['src']
assert data['notes']['src']['broken_targets'] == []
"
}

@test "audit errors when notes directory is missing" {
  rm -rf "$NOTES_CALLER_PWD/notes"

  run notes audit
  [ "$status" -ne 0 ]
  [[ "$output" == *"notes directory not found"* ]]
}

@test "audit handles empty notes directory cleanly" {
  run notes audit
  [ "$status" -eq 0 ]
  [[ "$output" == *"Scanned 0 note(s)"* ]]
  [[ "$output" == *"no notes have any links yet"* ]]
  [[ "$output" == *"Broken wikilink targets: none"* ]]
}
