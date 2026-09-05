<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="ccsession" width="400">
</picture>

<p><strong>Find and resume any Claude Code session — no <code>cd</code> required.</strong></p>

<p>
  Every Claude Code session, newest-active first, in one <code>fzf</code> picker — status, time,
  directory, branch, and summary at a glance. Press Enter and it drops into the session's own
  directory and resumes it for you.
</p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <a href="https://github.com/plabanauskis/cctools/releases"><img alt="Latest release: 1.0.0" src="https://img.shields.io/badge/release-1.0.0-D97757"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Claude Code" src="https://img.shields.io/badge/built%20for-Claude%20Code-D97757">
</p>

</div>

List every Claude Code session in an [`fzf`](https://github.com/junegunn/fzf)
picker and resume any one of them without first navigating to its directory.

Today, resuming a session means `cd`-ing to the right project directory and
running `claude --resume`. `ccsession` replaces that with a single command: it
lists all sessions newest-active-first — status, when, directory, branch, and
summary at a glance — and on Enter `cd`s into the chosen session's original
directory and runs `claude --resume <id>` there.

## What it looks like

```
  ccsession · 47 sessions · ↑↓ select · / filter · ⏎ resume

  ●  WHEN        DIRECTORY                               BRANCH    SUMMARY
  ─  ──────────  ──────────────────────────────────────  ────────  ──────────────────────────────
  ●  4m ago      ~/source/github/octocat/dashboard       main      Add CSV export to the reports page
  ●  7h ago      ~/Downloads/terraform-demo              —         Set up a Terraform demo environment
  ✗  8h ago      ~/…/octocat/dashboard                   main      Fix flaky end-to-end checkout tests
  ●  8h ago      /tmp/cchat.Xa9f2K                       —         Prototype a Redis caching layer
  ●  yesterday   ~/source/github/octocat/cli             master    Pull the latest changes
```

Highlighting a row shows a boxed preview card on the right:

```
┌─ session ──────────────────────────────────────┐
│ ● live                                         │
│                                                │
│ dir      ~/…/octocat/dashboard                 │
│ branch   main                                  │
│ active   2026-06-23 15:58 · 4m ago             │
│ id       3f1c8a40-6b2e-4d19-9c7a-1e5f0b8d2a64  │
├────────────────────────────────────────────────┤
│ Add CSV export to the reports page             │
└────────────────────────────────────────────────┘
```

## Requirements

`fzf`, `jq`, GNU `find`/`grep`/`date`/`stat`, and `claude` on your `PATH`.
(All standard on a typical Linux setup.)

## Install

Part of the [cctools](../../README.md) bundle:

```bash
cctools enable ccsession
```

(or select it during the root `install.sh`). The command is a symlink into the
bundle clone, so a `cctools update` is immediately live — no reinstall step.

## Usage

```bash
ccsession          # open the picker
ccsession --help   # show help
```

- Type to fuzzy-filter, ↑/↓ to move, Enter to resume, ESC to cancel.
- Rows marked `✗` (dimmed) are sessions whose directory no longer exists —
  e.g. ephemeral `/tmp/cchat.*` sessions after a reboot. They are shown for
  reference but cannot be resumed (pressing Enter on one prints an error and
  exits non-zero). Resuming requires the original directory because Claude
  locates sessions by their directory-derived project path.

## How it works

Sessions live at `~/.claude/projects/<encoded-dir>/<session-id>.jsonl`. For each
file `ccsession` reads:

| Field   | Source                                                       |
|---------|--------------------------------------------------------------|
| cwd     | first `"cwd"` value in the file                              |
| branch  | first `"gitBranch"` value (detached `HEAD`/none shown as `—`) |
| summary | latest `ai-title` record; else first user prompt; else id    |
| id      | the `.jsonl` filename stem                                    |
| active  | the file's mtime (drives sort order and "when")              |
| status  | `live` if the cwd still exists, else `gone`                  |

Columns are aligned by **character** count (not bytes) so the `●`/`✗`/`…`/`~`
glyphs line up under a UTF-8 locale.

## Tests

```bash
bash tests/ccsession.test.sh
```

A dependency-free bash suite that sources the script (it is written to be
sourceable) and asserts on its pure functions against synthetic session
fixtures.

## Out of scope (v1)

Deleting/renaming/archiving sessions, multi-select, opening a directory without
resuming, and searching within session contents.
