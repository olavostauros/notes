# notes

**Collective memory, encrypted.**

`notes` is a small CLI for keeping Markdown notes in a Git repo while protecting the private parts with `git-crypt`. It handles the boring-but-dangerous edges around encryption setup, collaborator keys, filename obfuscation, and staging files that Git would otherwise hide from you.

The shape is intentionally simple: write normal Markdown in `notes/`, let the tool keep encrypted filenames safe for GitHub, and use explicit commands when crossing encryption boundaries.

## Quick start

```sh
# One-time setup in a Git repo. This mutates encryption config and hooks.
notes setup --yes

# Add a note with YAML frontmatter.
notes new --slug project-plan --title "Project plan" --tags planning

# See note metadata.
notes list

# Check encryption + obfuscation state.
notes status

# Stage changed notes through notes' obfuscation/exclude rules.
notes stage notes/project-plan.md
```

For an existing encrypted repo:

```sh
notes setup --yes --unlock
notes status
```

## Daily workflow

```sh
# Show note changes against HEAD.
notes changes
notes changes --summary

# Stage modified/deleted notes. New notes should be explicit.
notes stage
notes stage notes/new-note.md

# Re-encrypt local files before handoff or archival.
notes lock --yes

# Decrypt again when you need to work locally.
notes unlock
```

`setup` and `lock` require confirmation because they mutate repository encryption state. In automation, pass `--yes` explicitly.

## What notes manages

- **Encryption setup** — initializes `git-crypt` through `rudi`, configures `.gitattributes`, and installs hooks.
- **Collaborator access** — adds GPG keys to the repo's encrypted key material.
- **Filename obfuscation** — stores notes with opaque filenames in Git while restoring readable names locally.
- **Manifest merging** — uses a custom merge driver for `notes/.manifest` so concurrent note additions can merge cleanly.
- **Safe staging** — stages notes despite local exclude/assume-unchanged rules used for readable working copies.

## Important gotchas

- `notes lock` currently re-encrypts **all git-crypt files in the repo**, not just `notes/` files. This is a `rudi` limitation tracked separately.
- Use `notes stage` for notes, not raw `git add notes/`; readable note names are intentionally excluded locally.
- After pulling shared note repos, inspect `notes status` and `notes changes --summary` before committing follow-up changes.

## Development

```sh
gh repo clone KnickKnackLabs/notes
cd notes
mise trust
mise install
mise run test
```

The test suite is BATS-based. Target a subset with:

```sh
mise run test test/encrypt.bats test/integration.bats
```

Tiny encrypted filing cabinet, very serious about labels.
