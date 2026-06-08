# notes#84 — Orphan detection in `notes status`

## What was done

Implemented orphan-file detection for removed features (`notes graph`, `notes index`).

**Problem:** Clones that ran `notes graph` or `notes index` before their removal still have stale `notes/graph.md` and `notes/index.md` on disk. These show up as "new" in `notes changes`, confuse `modules update`, and accumulate as background noise.

**Solution:** Three-part additive change:
1. `notes status` detects known orphan filenames and displays them as a new "Orphans" section (text + JSON output)
2. `notes clean --orphans` removes orphan files (and any manifest entries pointing to them)
3. BATS tests verify both detection and cleanup

## Files touched

| File | Change |
|------|--------|
| `.mise/tasks/status` | Added `ORPHAN_PATTERNS` array, orphan detection block, text output section, `orphans` field in JSON output (both locked and unlocked branches) |
| `.mise/tasks/clean` | **New** — task with `--orphans` flag that removes orphan files and manifest entries |
| `test/status.bats` | Added 6 new tests: text orphans (3), JSON orphans (3) |
| `test/clean.bats` | **New** — 7 tests covering clean detection, removal, manifest cleanup, non-orphan isolation |

## Design decisions

- **Curated allowlist, not heuristics** — `ORPHAN_PATTERNS=("graph.md" "index.md")` is a closed set. Future feature removals add to the list in the removing PR.
- **Don't auto-clean** — status displays, clean removes. User decides.
- **Don't tangle with `notes changes`** — orphans remain visible in changes until cleaned; status has a separate "Orphans" surface.
- **Versioned cleanup framework** — removing PRs add to the allowlist, following issue #84's pattern.

## Test results

### Baseline (before changes)
- 309 passing, 4 failing (known environmental `farts` failures — exit 127, not installed)

### After changes
- 322 passing, 4 failing (same 4 farts failures, unchanged)
- +13 new tests (6 status + 7 clean), zero regressions
- 3 existing status tests unchanged/skipped (locked-repo tests blocked on #39)

### New clean tests
| # | Test | Status |
|---|------|--------|
| 1 | reports no orphans when notes dir missing | ✅ |
| 2 | removes orphan file from disk | ✅ |
| 3 | removes multiple orphan files | ✅ |
| 4 | ignores non-orphan notes | ✅ |
| 5 | removes orphan and manifest entry | ✅ |
| 6 | no-op without --orphans flag | ✅ |
| 7 | shows count of removed files | ✅ |

### New status tests
| # | Test | Status |
|---|------|--------|
| 1 | shows Orphans section when orphan file exists | ✅ |
| 2 | shows no Orphans section when no orphan files | ✅ |
| 3 | shows multiple orphans when multiple exist | ✅ |
| 4 | --json has orphans field when orphan exists | ✅ |
| 5 | --json shows total 0 when no orphans | ✅ |
| 6 | --json shows unknown filename not orphan | ✅ |

## Caveats

- No env changes, no CI gotchas
- `farts` tests still fail (environmental — `farts` not installed)
- Notes has no lint gate (bats-only CI)
- Clean task gains execute permission on first chmod (`write` tool doesn't set +x)

## Status

Ready to push and open PR.

## Related

- Closes #84
- Companion issue #83 (graph removal) already merged as `5597acd`
- Companion 6cd9758 (index removal) already merged