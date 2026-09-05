<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="cochat" width="300">
</picture>

<p><strong>A throwaway Codex chat, in one command.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Codex" src="https://img.shields.io/badge/built%20for-Codex-10A37F">
</p>

</div>

Open Codex in a fresh temporary directory when a question does not belong in a project. `cochat` creates `${TMPDIR:-/tmp}/cochat.XXXXXX`, changes into it, and starts Codex; the shell you launched it from keeps its current directory.

The directory is intentionally retained. That lets its Codex session remain discoverable by `cosession` until the directory is removed (many systems clear `/tmp` at reboot). Remove it yourself when it is no longer useful.

## Requirements

- The `codex` command on `PATH`.
- Linux or macOS.

## Install

`cochat` is part of the [cotools](../../README.md) bundle:

```bash
cotools enable cochat
```

Or select it during the root `install.sh` flow.

## Usage

```bash
cochat                       # start in a new temporary directory
cochat --model gpt-5         # pass arguments through to codex unchanged
cochat --help                # show cochat help without launching Codex
```

All arguments after `cochat` pass through unchanged to `codex`. To find a retained chat later, run `cosession` and select its temporary-directory row.
