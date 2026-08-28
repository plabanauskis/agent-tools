<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
  <img src="assets/logo.svg" alt="pichat" width="300">
</picture>

<p><strong>A throwaway Pi chat, in one command.</strong></p>

<p>
  <a href="../../LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-555"></a>
  <img alt="Platform: Linux · macOS" src="https://img.shields.io/badge/platform-Linux%20%C2%B7%20macOS-555">
  <img alt="Built for Pi" src="https://img.shields.io/badge/built%20for-Pi-4B607C">
</p>

</div>

Open Pi in a fresh temporary directory when a question does not belong to a project. `pichat` creates `${TMPDIR:-/tmp}/pichat.XXXXXX`, changes into it, and starts Pi; the shell that launched it keeps its current directory.

The directory is intentionally retained, and Pi saves the conversation normally. This lets `pisession` discover and resume it until the directory is removed (many systems clear `/tmp` at reboot). Use Pi's own `--no-session` option when you want the conversation itself to be ephemeral.

## Requirements

- The `pi` command on `PATH`.
- Linux or macOS.

## Install

`pichat` is part of the [pitools](../../README.md) bundle:

```bash
pitools enable pichat
```

## Usage

```bash
pichat                              # start in a new temporary directory
pichat --model openai/gpt-5.6       # pass arguments through unchanged
pichat --no-session                 # leave no saved Pi session
pichat --help                       # show pichat help without launching Pi
```

All arguments after `pichat` pass through unchanged to `pi`.
