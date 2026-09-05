<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="cchat" width="300">
</picture>

<p><strong>A throwaway Claude Code chat, in one command — leaves no trace.</strong></p>

<p>
  For the quick question you don't want cluttering a real project. <code>cchat</code> drops you into
  Claude Code in a fresh temp dir and gets out of the way — your shell's working directory is
  untouched, and there's nothing to clean up afterward.
</p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <a href="https://github.com/plabanauskis/cctools/releases"><img alt="Latest release: 1.0.0" src="https://img.shields.io/badge/release-1.0.0-D97757"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Claude Code" src="https://img.shields.io/badge/built%20for-Claude%20Code-D97757">
</p>

</div>

Open Claude Code in a fresh, throwaway directory — for quick questions you don't
want cluttering a real project, and that you don't need to keep.

`cchat` makes a new temp dir under `$TMPDIR` (default `/tmp`), `cd`s into it, and
`exec`s `claude` there. Because it runs as its own process, your current shell's
working directory is untouched. The temp dir persists until reboot (so the
session is resumable until then — see `ccsession`).

## Requirements

`claude` on your `PATH`.

## Install

Part of the [cctools](../../README.md) bundle:

```bash
cctools enable cchat
```

(or select it during the root `install.sh`).

## Usage

```bash
cchat                 # fresh throwaway chat
cchat --model opus    # args pass straight through to claude
cchat --help          # show help
```
