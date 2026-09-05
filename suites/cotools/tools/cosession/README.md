<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="cosession" width="400">
</picture>

<p><strong>Find and resume any Codex session — no <code>cd</code> required.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Codex" src="https://img.shields.io/badge/built%20for-Codex-10A37F">
</p>

</div>

`cosession` scans local Codex rollouts and presents root sessions in an [`fzf`](https://github.com/junegunn/fzf) picker, newest-active first. Choose a live row and it changes to the original directory before running `codex resume <session-id>`.

## Picker

```
  cosession · 47 sessions · ↑↓ select · / filter · ⏎ resume

  ●  WHEN        DIRECTORY                               BRANCH    SUMMARY
  ─  ──────────  ──────────────────────────────────────  ────────  ──────────────────────────────
  ●  4m ago      ~/source/github/octocat/dashboard       main      Add CSV export to reports
  ●  7h ago      /tmp/cochat.Xa9f2K                      —         Try a parsing approach
  ✗  yesterday   ~/…/old-project                         main      Fix checkout tests
```

The right-hand preview shows the directory, branch, source, active time, session ID, and summary. `●` means the original directory is still present. `✗` means it is gone: the row remains useful as history but cannot be resumed.

## Requirements and install

`cosession` needs `fzf`, `jq`, and `codex` on `PATH`. It supports Linux and macOS. On Linux it uses the usual GNU `find`, `grep`, `date`, and `stat` interfaces; on macOS it uses the corresponding standard BSD `date` and `stat` forms, so GNU coreutils are not required there.

Install it from the [cotools](../../README.md) bundle:

```bash
cotools enable cosession
```

## Usage

```bash
cosession          # open the picker
cosession --help   # show help
```

Type to filter, use Up/Down to select, Enter to resume, or Escape to cancel.

## How discovery works

The state root is `CODEX_HOME` when set, otherwise `$HOME/.codex`. `cosession` recursively reads:

```text
${CODEX_HOME:-$HOME/.codex}/sessions/**/rollout-*.jsonl
```

It includes root user sessions from both Codex CLI and Codex Desktop. Structured internal-agent rollouts (for example child or guardian agents) are deliberately excluded; a valid included rollout must carry a session ID, working directory, and string source.

Each row is built from these rollout and metadata fields:

| Display field | Source |
| --- | --- |
| ID, directory, branch, source | the rollout's `session_meta` payload |
| Active | rollout file modification time |
| Summary | latest non-empty `thread_name` in `session_index.jsonl`; otherwise first non-empty matching `history.jsonl` text; otherwise the first usable user input in the rollout; otherwise the ID |
| Status | whether the recorded directory exists now |

Injected environment-context messages are not used as fallback summaries. Missing or malformed rollouts are skipped rather than producing misleading picker entries.

## Tests

```bash
bash tools/cosession/tests/cosession.test.sh
```

The Bash suite builds synthetic CLI, Desktop, internal-agent, malformed, live, and gone rollout fixtures. It also verifies summary precedence, picker rows, previews, and resume behavior.
