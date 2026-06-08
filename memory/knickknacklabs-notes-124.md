# Issue #124 — verify committed encrypted note blobs before publication

**Status:** Implemented, not yet PRed
**Date evaluated:** 2026-06-08
**Branch:** `feat/124-verify-committed-encrypted-blobs`
**Upstream baseline:** `09b01b1` upstream/main
**Tests:** 326 total, 322 pass, 4 expected `farts` skips (environmental). No regressions.

---

## What it is

Feature request for a `notes verify-blobs --ref HEAD` command that walks every tracked
blob under a notes-managed directory in a given git ref and checks it carries git-crypt
magic bytes (`\x00GITCRYPT\x00`). Prevents publishing plaintext content in encrypted
notes repos during fresh-history bootstrap.

## Acceptance criteria (from issue)

1. Fixture with all git-crypt-magic note blobs → ✅ passes
2. Fixture with plaintext `notes/.manifest` → ❌ fails
3. Fixture with one encrypted + one plaintext obfuscated blob → ❌ fails *and names the plaintext path*
4. Fixture with tracked readable `notes/status.md` → ❌ fails
5. Command works against a ref/tree without requiring checkout of readable working-tree files

## Liveness

- **No branch, PR, or partial implementation exists.** Zero comments on the issue.
- The existing `.mise/tasks/verify` is unrelated — it verifies GPG key fingerprints.
- Baseline tests: 313 tests, 309 pass, 4 expected `farts`-related skips (environmental). Healthy.

## Key code findings

| What | Where | Notes |
|------|-------|-------|
| Git-crypt magic detection | `.mise/tasks/setup` line 144 | `head -c 10 "$f" \| grep -q "GITCRYPT"` — inline, working tree only |
| Git-crypt magic format | Git-crypt spec | 10 bytes: `\x00 G I T C R Y P T \x00` (hex: `00 47 49 54 43 52 59 50 54 00`) |
| Simulated encrypted test fixtures | `test/encrypt.bats` line 207-208 | `printf '\x00GITCRYPT\x00' > "$TARGET_DIR/notes/test.md"` |
| `.gitattributes` pattern parser | `.mise/tasks/setup` lines 60-69 | `gitattributes_has_encrypted_pattern()` — local function, checks `$1 == pattern && filter=git-crypt` |
| Manifest helpers | `lib/common.sh` lines 60-89 | `manifest_id_for_name`, `manifest_has_id`, `manifest_name_for_id` — all local-file only (need ref-aware versions) |
| Blob-from-ref extraction | none | No existing usage of `git show <ref>:<path>` or `git ls-tree -r <ref>` in lib/ or tasks |
| Notes directory resolution | `lib/common.sh` lines 47-55 | `resolve_notes_dir()` — resolves abs path to relative |

## Files changed

| File | Change |
|------|--------|
| `.mise/tasks/verify-blobs` | New — the verify-blobs command (~80 lines bash) |
| `test/verify-blobs.bats` | New — 13 test cases covering all ACs + edge cases |
| `memory/knickknacklabs-notes-124.md` | This file |

## Implementation sketch

**Files to create:**
- `.mise/tasks/verify-blobs` — the new command (~80 lines bash)

**Files to modify:**
- `test/verify-blobs.bats` — new test file (~60 lines bats)

**Core detection primitive:**
```bash
# Returns 0 if the blob at <ref>:<path> has git-crypt magic bytes
_verify_blob_encrypted() {
  local ref="$1" path="$2"
  git show "$ref:$path" 2>/dev/null | head -c 10 | grep -q $'\x00'"GITCRYPT"
}
```

**Pipeline for each AC scenario:**
1. Read manifest from ref: `git show "$ref:notes/.manifest"`
2. List tracked blob paths: `git ls-tree -r "$ref" -- notes/`
3. Match tracked paths against encrypted surface patterns from `git show "$ref:.gitattributes"`
4. Check each obfuscated blob ID for magic bytes
5. Check for tracked readable `.md` files (wrong — only hex IDs should be tracked)

**Test strategy:** Each AC maps to a test case. All operations against a ref, no working tree needed. Use `printf '\x00GITCRYPT\x00'` for encrypted fixtures, plain echo for plaintext fixtures.

**13 test cases:**
1. All encrypted blobs pass
2. Plaintext manifest fails
3. Mixed encryption fails + names plaintext path
4. Tracked readable .md fails
5. Works against a ref without checkout (branch ref, not HEAD)
6. Nonexistent ref fails
7. No notes directory fails
8. `--dir` flag works for custom notes path
9. Empty notes directory with plaintext manifest fails
10. Subdirectory notes checked
11. Unencrypted subdirectory note detected
12. `--strict` fails on dirty working tree
13. `--strict` passes on clean working tree

## Bugs found during implementation

**Bash 3.2 `set -u` + array expansion in `suppress.sh`** (#44): Confirmed still live. `set_status_suppression` and `clear_status_suppression` call `add_exclude_entries`/`remove_exclude_entries` with `"${scoped_ids[@]}"` unconditionally from their full-mode paths (lines 229, 261). On macOS bash 3.2, expanding an empty declared array can trigger nounset errors.

**`notes changes --summary` + encrypted manifest:** `detect_changes` cannot parse a binary (encrypted) manifest to find tracked IDs, so it reports "No changes" even when the working tree differs. Tests for `--strict` must simulate an unlocked repo (readable manifest on disk).

## Risks

- No `rudi`/`git-crypt` needed for the command to run (only `git show` pipes), but tests must simulate encrypted content
- `git show` of large blobs is lazy via pipe, but for repos with thousands of notes the loop may be slow
- Name collision with existing `verify` task — use `verify-blobs` as task name

## Open questions

1. Should the encrypted surface be auto-detected from `.gitattributes` in the ref, or accept `--pattern` override?
2. Should tracked readable `.md` files be a hard failure (exit 1) or a warning (exit 0 with stderr)?
   - Current AC says "fails" — so hard failure.
3. Should `--strict` mode check working tree cleanliness via `notes changes --summary`?
   - Issue says "optionally" — keep as flag, not default.
4. Should command auto-detect notes directory or require `--dir`?
   - Issue shows `--dir notes` as optional — default to `notes/`.
5. Default `--ref` value: `HEAD` (current tip of current branch).

## Related

- Issue: https://github.com/KnickKnackLabs/notes/issues/124
- Real-world trigger: `ricon-family/fold` home-bootstrap work, `homes:publish-fresh` needed this check
- Previous approach (flawed): homes checked only manifest + one representative blob — reviewer found the hole
- Current workaround: `homes:publish-fresh` manually walks every tracked path (fragile, duplicated logic)