<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="pisession" width="400">
</picture>

<p><strong>Find and resume any Pi session — no <code>cd</code> required.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Pi" src="https://img.shields.io/badge/built%20for-Pi-4B607C">
</p>

</div>

`pisession` scans saved Pi JSONL sessions across all working directories and presents them in an [`fzf`](https://github.com/junegunn/fzf) picker, newest-active first. Choose a live row and it changes to the recorded directory before running `pi --session <file>`.

Pi already provides `pi -r` and `/resume` for the current project. `pisession` complements that picker with a single global view.

## Picker

```text
  pisession · 47 sessions · ↑↓ select · / filter · ⏎ resume

  ●  WHEN        DIRECTORY                               MODEL                 SUMMARY
  ─  ──────────  ──────────────────────────────────────  ────────────────────  ──────────────────────────────
  ●  4m ago      ~/source/github/octocat/dashboard       anthropic/claude-so…  Add CSV export to reports
  ●  7h ago      /tmp/pichat.Xa9f2K                      openai-codex/gpt-5.6  Try a parsing approach
  ✗  yesterday   ~/…/old-project                         google/gemini-3-pro   Fix checkout tests
```

The right-hand preview shows directory status, model, Pi session format version, active time, session ID, and summary. `●` means the original directory is present. `✗` means it is gone; the row remains visible as history but cannot be resumed.

## Requirements and install

`pisession` needs `fzf`, `jq`, and `pi` on `PATH`. It supports Linux and macOS and uses each platform's standard `date` and `stat` forms.

```bash
pitools enable pisession
```

## Usage

```bash
pisession          # open the global picker
pisession --help   # show help
```

Type to filter, use Up/Down to select, Enter to resume, or Escape to cancel.

## Session discovery

The default session root is:

```text
${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/sessions
```

`PI_CODING_AGENT_SESSION_DIR` overrides that location, matching Pi's own precedence. `pisession` recursively finds `*.jsonl`, then includes only files with a valid Pi session header containing a UUID, working directory, and numeric format version.

Each row comes directly from Pi's documented session format:

| Display field | Source |
| --- | --- |
| ID, directory, format | `type: "session"` header |
| Model | latest `model_change`, otherwise latest assistant provider/model |
| Active | session file modification time |
| Summary | latest non-empty `session_info.name`; otherwise first user text; otherwise ID |
| Status | whether the recorded working directory exists |

Malformed JSONL and unrelated exports are skipped. Summaries are normalized to one delimiter-safe line. On resume, the exact file path is passed to Pi rather than relying on a partial ID.

## Tests

```bash
bash tools/pisession/tests/pisession.test.sh
```

The suite builds synthetic v2/v3, named, unnamed, live, gone, and malformed Pi sessions and verifies parsing, ordering, previews, Linux/macOS utility behavior, and the `pi --session` launch boundary.
