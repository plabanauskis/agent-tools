# cotools Codex Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tested, documented, independently branded Codex-native port of the cctools suite with cochat, cosession, cobox, and the cotools lifecycle manager.

**Architecture:** Port the Bash bundle structure from cctools commit 84c9773, keeping manifests and lifecycle behavior stable while replacing each Claude-specific runtime boundary with a Codex-native one. cosession parses active Codex rollout JSONL and metadata indexes; cobox mounts the exact host Codex installation and state into the existing Docker + sysbox boundary.

**Tech Stack:** Bash, jq, fzf, Git, Docker, sysbox-runc, SVG, ImageMagick, plain Bash tests, shellcheck, shfmt

**Spec:** docs/superpowers/specs/2026-08-26-cotools-codex-port-design.md

## Global Constraints

- Parity baseline is cctools commit 84c9773 (ccbox-v1.1.0).
- Public commands are exactly cotools, cochat, cosession, and cobox.
- Public bundle variables use COTOOLS_*; box variables/resources use COBOX_*/cobox-*.
- All three tools start at version 1.0.0.
- cochat and cosession support Linux and macOS; cobox supports Linux only.
- cosession includes root CLI/Desktop sessions and excludes structured-source internal agent sessions.
- cobox uses sysbox and --dangerously-bypass-approvals-and-sandbox; it never mounts the host Docker socket, SSH credentials, or GitHub credentials.
- Codex state defaults to $HOME/.codex and honors CODEX_HOME; cobox mounts it read-write.
- Node Trail assets use #10A37F, retain source silhouettes, and do not embed or imitate the OpenAI Blossom.
- Installation remains sudo-free at $HOME/.local/share/cotools plus $HOME/.local/bin unless overridden.
- Shell behavior changes follow test-first red-green-refactor cycles.
- Keep the repository local: configure no remote and do not push or create a GitHub repository.

## File Responsibility Map

- lib/cotools-common.sh: manifest helpers.
- bin/cotools: lifecycle manager and managed-prefix update.
- install.sh: clone/update, selection, links, and summary.
- scripts/release.sh: per-tool versions, changelogs, tags, and optional releases.
- scripts/check.sh: syntax, lint, format, tests, assets, and gated cobox smoke.
- tools/cochat/cochat: ephemeral Codex launcher.
- tools/cosession/cosession: rollout discovery, extraction, picker, and resume.
- tools/cobox/bin/cobox: install detection, diagnostics, Docker mounts, and launch.
- tools/cobox/entrypoint.sh and Dockerfile: inner Docker and toolchain image.
- tools/*/assets: Node Trail identity.
- README.md and tools/*/README.md: user documentation.

---

### Task 1: Bundle Manifest Contract and Lifecycle Manager

**Files:**

- Create: .gitignore
- Create: LICENSE
- Create: lib/cotools-common.sh
- Create: bin/cotools
- Create: tools/cochat/tool.manifest
- Create: tools/cochat/VERSION
- Create: tools/cosession/tool.manifest
- Create: tools/cosession/VERSION
- Create: tools/cobox/tool.manifest
- Create: tools/cobox/VERSION
- Create: tests/cotools.test.sh

**Interfaces:**

- Consumes: PATH, COTOOLS_HOME, COTOOLS_BIN, and manifests.
- Produces: current_os(), list_tools(), load_manifest(tool), platform_ok(), missing_deps(), tool_version(tool), entrypoint_path(tool), tool_enabled(), enable_tool(tool), disable_tool(tool), update_prefix(dir), and cotools.

- [ ] **Step 1: Write the failing manager and manifest test**

Port the source harness to tests/cotools.test.sh. Use a private fake PATH and assert:

~~~bash
export COTOOLS_HOME="$REPO"
export COTOOLS_BIN="$SANDBOX/bin"
for dep in codex fzf jq docker sysbox-runc; do
  printf '#!/usr/bin/env bash\n' >"$FAKEBIN/$dep"
  chmod +x "$FAKEBIN/$dep"
done
export PATH="$FAKEBIN:$PATH"
source "$REPO/bin/cotools"

assert_eq "$(list_tools | sort | tr '\n' ' ')" "cobox cochat cosession " "all tools"
load_manifest cochat
assert_eq "$DEPS" "codex" "cochat dependencies"
load_manifest cosession
assert_eq "$DEPS" "fzf jq codex" "cosession dependencies"
load_manifest cobox
assert_eq "$DEPS" "docker sysbox-runc codex" "cobox dependencies"
assert_eq "$(tool_version cochat)" "1.0.0" "cochat version"
assert_eq "$(tool_version cosession)" "1.0.0" "cosession version"
assert_eq "$(tool_version cobox)" "1.0.0" "cobox version"
~~~

Retain enable/disable symlink assertions and temporary bare-remote history-rewrite checks for update_prefix.

- [ ] **Step 2: Run the manager test and verify the expected failure**

~~~bash
bash tests/cotools.test.sh
~~~

Expected: nonzero because bin/cotools does not exist.

- [ ] **Step 3: Implement manifests, shared helpers, and manager**

Port lib/cctools-common.sh and bin/cctools from the parity baseline. Apply the naming matrix literally. Preserve symlink ownership, Bash 3.2 guards, dirty-tree refusal, upstream lookup, fetch --prune, and reset --hard "$upstream".

Manifest values:

~~~text
cochat: NAME=cochat; ENTRYPOINT=cochat; COMMANDS=cochat; DEPS=codex; PLATFORM="linux macos"
cosession: NAME=cosession; ENTRYPOINT=cosession; COMMANDS=cosession; DEPS="fzf jq codex"; PLATFORM="linux macos"
cobox: NAME=cobox; ENTRYPOINT=bin/cobox; COMMANDS=cobox; DEPS="docker sysbox-runc codex"; PLATFORM=linux
~~~

Use the descriptions and post-enable text from the spec. Write 1.0.0 to every VERSION. Rename Docker reminders to cobox:latest, cobox-, and cobox uninstall.

Set .gitignore to:

~~~gitignore
*.swp
*~
.DS_Store
.superpowers/
~~~

Copy the source MIT license unchanged.

- [ ] **Step 4: Run test, syntax, lint, and formatting checks**

~~~bash
bash tests/cotools.test.sh
bash -n lib/cotools-common.sh bin/cotools tests/cotools.test.sh
shellcheck -x lib/cotools-common.sh bin/cotools tests/cotools.test.sh
shfmt -i 2 -ci -d lib/cotools-common.sh bin/cotools tests/cotools.test.sh
~~~

Expected: every command passes with no formatter diff.

- [ ] **Step 5: Commit the lifecycle core**

~~~bash
git add .gitignore LICENSE lib bin tests/cotools.test.sh tools/*/tool.manifest tools/*/VERSION
git commit -m "feat: add cotools lifecycle manager"
~~~

---

### Task 2: Installer

**Files:**

- Create: install.sh
- Create: tests/install.test.sh

**Interfaces:**

- Consumes: Task 1 helpers; Git; COTOOLS_REPO, COTOOLS_HOME, COTOOLS_BIN, COTOOLS_BRANCH.
- Produces: load_lib(), clone_or_update(), link_tool(tool), selectors, summary, and installer CLI.

- [ ] **Step 1: Write the failing installer test with an isolated Git source**

Create tests/install.test.sh. Source install.sh under COTOOLS_TEST_SOURCE=1. Build a cloneable fixture from current working-tree files:

~~~bash
make_source_repo() {
  local source="$SANDBOX/source"
  mkdir -p "$source"
  (cd "$REPO" && tar --exclude=.git --exclude=.superpowers -cf - .) |
    (cd "$source" && tar -xf -)
  git -C "$source" init -q -b main
  git -C "$source" config user.email test@example.invalid
  git -C "$source" config user.name cotools-test
  git -C "$source" add .
  git -C "$source" commit -q -m fixture
  printf '%s' "$source"
}
~~~

Use fake codex, fzf, and jq. Run the real installer against file://$source_repo with --tools=cochat,cosession. Assert prefix clone, cochat/cosession/cotools links, absent cobox link, cotools summary, and idempotent rerun.

- [ ] **Step 2: Run the installer test and verify the expected failure**

~~~bash
bash tests/install.test.sh
~~~

Expected: nonzero because install.sh does not exist.

- [ ] **Step 3: Implement the installer**

Port the source installer with these exact defaults:

~~~text
COTOOLS_REPO default: https://github.com/plabanauskis/cotools.git
COTOOLS_HOME default: $HOME/.local/share/cotools
COTOOLS_BIN default: $HOME/.local/bin
COTOOLS_BRANCH default: main
~~~

Set COTOOLS_TOOLS_DIR before sourcing lib/cotools-common.sh. Preserve --all, --tools=, --force, TTY detection, Bash 3.2 guards, dependency-aware automatic selection, and the always-installed cotools link.

- [ ] **Step 4: Run test, syntax, lint, and formatting checks**

~~~bash
bash tests/install.test.sh
bash -n install.sh tests/install.test.sh
shellcheck -x install.sh tests/install.test.sh
shfmt -i 2 -ci -d install.sh tests/install.test.sh
~~~

Expected: every command passes.

- [ ] **Step 5: Commit the installer**

~~~bash
git add install.sh tests/install.test.sh
git commit -m "feat: add selective cotools installer"
~~~

---

### Task 3: cochat

**Files:**

- Create: tools/cochat/cochat
- Create: tools/cochat/tests/cochat.test.sh
- Create: tools/cochat/CHANGELOG.md

**Interfaces:**

- Consumes: TMPDIR, codex on PATH, and arbitrary Codex arguments.
- Produces: cochat in a unique retained temp directory.

- [ ] **Step 1: Write the failing cochat behavior test**

Create a fake codex recorder:

~~~bash
printf '#!/usr/bin/env bash\necho "CWD=$PWD"\nprintf "ARG=<%s>\\n" "$@"\n' >"$FAKEBIN/codex"
chmod +x "$FAKEBIN/codex"
out="$(TMPDIR="$SANDBOX" PATH="$FAKEBIN:$PATH" bash "$COCHAT" --model gpt-5.6-sol "two words")"
assert_contains "$out" "CWD=$SANDBOX/cochat." "fresh cochat directory"
assert_contains "$out" "ARG=<--model>" "preserves option"
assert_contains "$out" "ARG=<gpt-5.6-sol>" "preserves value"
assert_contains "$out" "ARG=<two words>" "preserves boundaries"
~~~

Also assert --help exits zero, names cochat, and does not emit CWD=.

- [ ] **Step 2: Run the test and verify the expected failure**

~~~bash
bash tools/cochat/tests/cochat.test.sh
~~~

Expected: nonzero because tools/cochat/cochat does not exist.

- [ ] **Step 3: Implement cochat and changelog**

Implement strict mode, tool-specific help, mktemp -d under TMPDIR with /tmp fallback, cd, and exec codex "$@". Help states args pass unchanged and cosession can resume retained sessions. Create a 1.0.0 changelog dated 2026-08-26.

- [ ] **Step 4: Run focused verification**

~~~bash
bash tools/cochat/tests/cochat.test.sh
bash -n tools/cochat/cochat tools/cochat/tests/cochat.test.sh
shellcheck -x tools/cochat/cochat tools/cochat/tests/cochat.test.sh
shfmt -i 2 -ci -d tools/cochat/cochat tools/cochat/tests/cochat.test.sh
~~~

Expected: every command passes.

- [ ] **Step 5: Commit cochat**

~~~bash
git add tools/cochat
git commit -m "feat: add ephemeral Codex chats"
~~~

---

### Task 4: cosession

**Files:**

- Create: tools/cosession/cosession
- Create: tools/cosession/tests/cosession.test.sh
- Create: tools/cosession/CHANGELOG.md

**Interfaces:**

- Consumes: CODEX_HOME/sessions, session_index.jsonl, history.jsonl, jq, fzf, GNU find/date/stat/grep, and codex resume.
- Produces: dir_status(cwd), relative_time(epoch, now), fit(text, width), trunc(text, width), shorten_dir(path, width), session_meta(rollout), is_root_session(rollout), session_summary(rollout, id), extract_session(rollout), build_row(rollout, mtime, now), build_list(now), render_preview(rollout), and launch(rollout). session_meta emits `id<SEP>cwd<SEP>branch<SEP>source`; extract_session emits `cwd<SEP>branch<SEP>summary<SEP>id<SEP>source`.

- [ ] **Step 1: Read the test-quality rules**

Read test-driven-development/writing-good-tests.md beside the TDD skill completely. For every assertion, name the production behavior whose removal makes it fail. Assert emitted metadata and real recorder output, not call counts.

- [ ] **Step 2: Write failing rollout and picker tests**

Build a private CODEX_HOME with dated session directories. Include CLI, Desktop, and structured subagent fixtures:

~~~json
{"timestamp":"2026-08-26T10:00:00Z","type":"session_meta","payload":{"id":"11111111-1111-4111-8111-111111111111","cwd":"__LIVE_CWD__","source":"cli","originator":"codex-tui","git":{"branch":"main"}}}
{"timestamp":"2026-08-26T10:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"CLI fallback summary"}]}}
~~~

~~~json
{"timestamp":"2026-08-26T11:00:00Z","type":"session_meta","payload":{"id":"22222222-2222-4222-8222-222222222222","cwd":"__DESKTOP_CWD__","source":"vscode","originator":"Codex Desktop"}}
{"timestamp":"2026-08-26T11:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<environment_context>generated context</environment_context>"}]}}
{"timestamp":"2026-08-26T11:00:02Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"Desktop fallback summary"}]}}
~~~

~~~json
{"timestamp":"2026-08-26T12:00:00Z","type":"session_meta","payload":{"id":"33333333-3333-4333-8333-333333333333","cwd":"__LIVE_CWD__","source":{"subagent":{"thread_spawn":{"parent_thread_id":"11111111-1111-4111-8111-111111111111","depth":1}}}}}
~~~

Add two session_index rows for the CLI UUID so the latest nonempty name wins. Add a history row for Desktop so history wins over rollout. Add malformed fixtures missing UUID and cwd.

Assertions:

~~~bash
assert_eq "$(session_summary "$cli_rollout" "$cli_id")" "Renamed CLI thread" "latest name"
assert_eq "$(session_summary "$desktop_rollout" "$desktop_id")" "Desktop prompt from history" "history precedence"
assert_eq "$(is_root_session "$subagent_rollout" && echo yes || echo no)" "no" "subagent excluded"
assert_eq "$(build_list 1787738400 | grep -c "$subagent_id")" "0" "picker omits subagent"
~~~

Retain source formatting, header, live/gone row, preview, and gone-directory tests. Add a fake codex recorder; live launch must record the original cwd plus exactly resume and UUID.

- [ ] **Step 3: Run the test and verify the expected failure**

~~~bash
bash tools/cosession/tests/cosession.test.sh
~~~

Expected: nonzero because tools/cosession/cosession does not exist.

- [ ] **Step 4: Implement extraction and summary precedence**

CODEX_ROOT is CODEX_HOME when set, otherwise $HOME/.codex. Define SESSIONS, INDEX, HISTORY, and SEP (ASCII unit separator) from it.

Read first session_meta with jq. Emit UUID (id then session_id), cwd, branch, and string source joined by SEP. is_root_session requires nonempty UUID, cwd, and string source.

Use jq -rs and last() for latest matching nonempty thread_name. Use the first matching nonempty history text. For rollout fallback, choose first nonempty user input_text that does not begin with <environment_context>. Collapse whitespace and strip tabs, newlines, and SEP. Fall back to UUID.

- [ ] **Step 5: Implement discovery, picker, preview, and resume**

Use recursive find of rollout-*.jsonl, mtime sort descending, then skip anything failing is_root_session. Feed integer mtime to build_row.

Keep source fzf flags and add source to the preview. launch parses cwd and UUID, changes into a live cwd, and executes:

~~~bash
exec codex resume "$id"
~~~

No valid rows prints no Codex sessions found under the sessions path and returns 1.

- [ ] **Step 6: Run focused verification**

~~~bash
bash tools/cosession/tests/cosession.test.sh
bash -n tools/cosession/cosession tools/cosession/tests/cosession.test.sh
shellcheck -x tools/cosession/cosession tools/cosession/tests/cosession.test.sh
shfmt -i 2 -ci -d tools/cosession/cosession tools/cosession/tests/cosession.test.sh
~~~

Expected: extraction, filtering, precedence, formatting, preview, and launch checks pass.

- [ ] **Step 7: Commit cosession**

~~~bash
git add tools/cosession
git commit -m "feat: add Codex session picker"
~~~

---

### Task 5: cobox Host Launcher

**Files:**

- Create: tools/cobox/bin/cobox
- Create: tools/cobox/tests/cobox.test.sh
- Create: tools/cobox/CHANGELOG.md

**Interfaces:**

- Consumes: Docker, sysbox-runc, host codex, CODEX_HOME, Git context, COBOX_*, optional OPENAI_API_KEY/CODEX_ACCESS_TOKEN, and Task 6 build context.
- Produces: find_share_dir(), resolve_codex_install(candidate), cobox_build(), cobox_doctor(), cobox_uninstall(), build_docker_args(repo_root, kind, codex_exec, mount_source), and cobox. resolve_codex_install emits `kind<SEP>executable<SEP>mount_source`; build_docker_args populates the global `DOCKER_ARGS` Bash array.

- [ ] **Step 1: Write failing install-detection tests**

The launcher must be sourceable. Create:

~~~bash
npm_pkg="$SANDBOX/npm/lib/node_modules/@openai/codex"
mkdir -p "$npm_pkg/bin" "$npm_pkg/node_modules/@openai/codex-linux-x64/vendor"
printf '{"name":"@openai/codex","version":"9.9.9"}\n' >"$npm_pkg/package.json"
printf '#!/usr/bin/env node\n' >"$npm_pkg/bin/codex.js"
chmod +x "$npm_pkg/bin/codex.js"

native="$SANDBOX/native/codex"
mkdir -p "$(dirname "$native")"
printf '\177ELFfake-codex\n' >"$native"
chmod +x "$native"

unsupported="$SANDBOX/custom/codex"
mkdir -p "$(dirname "$unsupported")"
printf '#!/usr/bin/env bash\n' >"$unsupported"
chmod +x "$unsupported"
~~~

Assert npm emits npm plus codex.js plus npm_pkg; native emits native and its path twice; unsupported fails with an actionable supported-layout message.

- [ ] **Step 2: Write failing Docker-argument and launch-gate tests**

Use fake docker and an isolated Git repo. Assert docker run includes sysbox runtime, COBOX=1, CODEX_HOME, repo/state mounts, read-only npm package, cobox-docker project volume, and --dangerously-bypass-approvals-and-sandbox. Assert arbitrary Codex args follow the bypass flag without splitting. Assert optional auth env vars are present only when set. Retain the non-Git unattended-abort test; Task 6 adds build-context coverage when the Dockerfile exists.

- [ ] **Step 3: Run the test and verify the expected failure**

~~~bash
bash tools/cobox/tests/cobox.test.sh
~~~

Expected: nonzero because tools/cobox/bin/cobox does not exist.

- [ ] **Step 4: Implement sourceable dispatch and install detection**

Define version 1.0.0, image default cobox:latest, CODEX_ROOT, renamed caches, and SEP.

resolve_codex_install:

1. Resolve command -v codex or explicit candidate via readlink -f.
2. Require executable regular file.
3. Match @openai/codex/bin/codex.js, derive package root, verify package.json name.
4. Reject any other #! script.
5. Treat remaining executable as native.
6. Emit kind, executable, and mount source with SEP.

Put dispatch and launch in main(), guarded by BASH_SOURCE.

- [ ] **Step 5: Implement doctor, lifecycle, and Docker args**

Port build, uninstall, non-Git confirmation, missing-image prompt, and tint under cobox names. Doctor checks Docker, sysbox runtime, resolved install, Codex state directory, codex login status, and image.

Build Docker args as a Bash array. Mount npm package or native binary read-only at identical path, Codex state/project read-write, .gitconfig read-only, and export CODEX_HOME. Pass auth env vars only when set. Use .cobox/ports and all COBOX_* names/resources.

- [ ] **Step 6: Run focused verification**

~~~bash
bash tools/cobox/tests/cobox.test.sh
bash -n tools/cobox/bin/cobox tools/cobox/tests/cobox.test.sh
shellcheck -x tools/cobox/bin/cobox tools/cobox/tests/cobox.test.sh
shfmt -i 2 -ci -d tools/cobox/bin/cobox tools/cobox/tests/cobox.test.sh
~~~

Expected: detection, mounts, flags, env, and gate checks pass without real Docker.

- [ ] **Step 7: Commit cobox launcher**

~~~bash
git add tools/cobox/bin/cobox tools/cobox/tests/cobox.test.sh tools/cobox/CHANGELOG.md
git commit -m "feat: add sandboxed Codex launcher"
~~~

---

### Task 6: Container and Repository Automation

**Files:**

- Create: tools/cobox/entrypoint.sh
- Create: tools/cobox/Dockerfile
- Create: tools/cobox/test/smoke.sh
- Modify: tools/cobox/tests/cobox.test.sh
- Create: tests/release.test.sh
- Create: scripts/release.sh
- Create: scripts/check.sh
- Create: scripts/dev-setup.sh
- Create: .githooks/pre-push

**Interfaces:**

- Consumes: versions/manifests, cobox build path, Docker build args, shellcheck, shfmt, ImageMagick outputs, and Git.
- Produces: image, entrypoint, smoke test, release helpers, check runner, and pre-push hook.

- [ ] **Step 1: Write failing container-contract tests**

Extend tools/cobox/tests/cobox.test.sh with the baseline symlink-safe Dockerfile discovery test: invoke cobox build through a symlink, point COBOX_SHARE_DIR at an empty directory, stub docker, and assert resolution to the real tools/cobox directory. Add static assertions for Node, Go, and .NET version arguments, absence of an `@openai/codex` install, and `/etc/profile.d/cobox-toolchains.sh`. Add an entrypoint test with fake docker that verifies COBOX_NO_DOCKER=1 skips daemon startup and still executes the requested command.

- [ ] **Step 2: Run container-contract tests and verify the expected failure**

~~~bash
bash tools/cobox/tests/cobox.test.sh
~~~

Expected: nonzero because Dockerfile and entrypoint.sh do not exist.

- [ ] **Step 3: Write failing release-helper tests**

Port release tests to COTOOLS_HOME. Assert semantic versions, cochat VERSION/changelog insertion, and cobox VERSION plus embedded COBOX_VERSION sync.

- [ ] **Step 4: Run release tests and verify the expected failure**

~~~bash
bash tests/release.test.sh
~~~

Expected: nonzero because scripts/release.sh does not exist.

- [ ] **Step 5: Implement release and developer scripts**

Port release.sh with renamed roots/tools/tags and embedded version sync. Tags are <tool>-vX.Y.Z. Keep optional --gh but do not invoke it. Port dev-setup and pre-push so the hook runs scripts/check.sh.

- [ ] **Step 6: Implement image, entrypoint, and smoke**

Port Dockerfile toolchains, changing only brand/comments. Do not install Codex. Keep Node 24, Python/uv, Go 1.26.4, Rust stable, .NET 10, GitHub CLI, inner Docker, mirrored account, and cobox-toolchains.sh.

entrypoint.sh uses strict mode, derives a default-zero COBOX_NO_DOCKER value without triggering nounset, starts dockerd unless disabled/already running, then execs all args. Port smoke with cobox:latest, identical toolchain/non-root checks, and sysbox-gated inner Docker.

- [ ] **Step 7: Add the check runner**

check.sh lists owned shell files, discovers tests, and runs syntax, shellcheck, shfmt, all existing suites, then gated smoke. Final messages are check.sh: ALL CHECKS PASSED or check.sh: SOME CHECKS FAILED. Task 7 adds the asset suite to automatic test discovery.

- [ ] **Step 8: Run focused verification**

~~~bash
bash tests/release.test.sh
bash tools/cobox/tests/cobox.test.sh
bash -n scripts/*.sh .githooks/pre-push tools/cobox/entrypoint.sh tools/cobox/test/smoke.sh
shellcheck -x scripts/*.sh .githooks/pre-push tools/cobox/entrypoint.sh tools/cobox/test/smoke.sh
shfmt -i 2 -ci -d scripts/*.sh .githooks/pre-push tools/cobox/entrypoint.sh tools/cobox/test/smoke.sh
~~~

Expected: release, container-contract, and shell checks pass.

- [ ] **Step 9: Commit container and automation**

~~~bash
git add tools/cobox/entrypoint.sh tools/cobox/Dockerfile tools/cobox/test tools/cobox/tests/cobox.test.sh tests/release.test.sh scripts .githooks
git commit -m "build: add cobox image and project checks"
~~~

---

### Task 7: Node Trail Brand Assets

**Files:**

- Create: tools/cochat/assets/icon.svg
- Create: tools/cochat/assets/icon-dark.svg
- Create: tools/cochat/assets/logo.svg
- Create: tools/cochat/assets/logo-dark.svg
- Create: tools/cochat/assets/og-image.svg
- Create: tools/cochat/assets/og-image.png
- Create: tools/cosession/assets/icon.svg
- Create: tools/cosession/assets/icon-dark.svg
- Create: tools/cosession/assets/logo.svg
- Create: tools/cosession/assets/logo-dark.svg
- Create: tools/cosession/assets/og-image.svg
- Create: tools/cosession/assets/og-image.png
- Create: tools/cobox/assets/icon.svg
- Create: tools/cobox/assets/icon-dark.svg
- Create: tools/cobox/assets/logo.svg
- Create: tools/cobox/assets/logo-dark.svg
- Create: tools/cobox/assets/og-image.svg
- Create: tools/cobox/assets/og-image.png
- Create: tests/assets.test.sh

**Interfaces:**

- Consumes: approved Node Trail direction, source dimensions/silhouettes, convert, xmllint, identify.
- Produces: light/dark icons and wordmarks plus 1280x640 social SVG/PNG.

- [ ] **Step 1: Write the failing asset test**

Create tests/assets.test.sh. Require all 18 paths, parse every SVG with `xmllint --noout`, verify all three PNGs identify as 1280x640, and reject source names plus `#D97757` in assets.

- [ ] **Step 2: Run asset test and verify the expected failure**

~~~bash
bash tests/assets.test.sh
~~~

Expected: nonzero with missing asset paths.

- [ ] **Step 3: Create icon and wordmark SVGs**

Use source dimensions and silhouettes. Apply exact motifs:

- cochat: chat bubble with three horizontal green circles at decreasing opacity.
- cosession: three rows, green active row, and three vertical green circles.
- cobox: green top face, dark/cream side faces, and three light nodes on top.

Every SVG has role=img, accurate aria-label, and title. Light uses #16181D ink; dark uses #F4F1EA. Accent and co prefix use #10A37F. No OpenAI mark and no #D97757.

- [ ] **Step 4: Create social SVGs**

Keep 1280x640, #14161B background, faint oversized silhouette, centered icon, wordmark, two headline lines, and cotools footer.

Headlines:

~~~text
cochat: A throwaway Codex chat, in one command. / Leaves no trace.
cosession: Find and resume any Codex session / — no cd required.
cobox: Give Codex full control of your project, / never of your computer.
~~~

Footer: github.com/plabanauskis/cotools.

- [ ] **Step 5: Render PNGs**

~~~bash
convert tools/cochat/assets/og-image.svg tools/cochat/assets/og-image.png
convert tools/cosession/assets/og-image.svg tools/cosession/assets/og-image.png
convert tools/cobox/assets/og-image.svg tools/cobox/assets/og-image.png
~~~

Expected: three 1280x640 PNG files.

- [ ] **Step 6: Verify and visually inspect**

~~~bash
bash tests/assets.test.sh
identify tools/*/assets/og-image.png
~~~

Open all PNGs with the available image viewer. Check silhouettes, node placement, wordmarks, headline wrapping, footer, and clearance. Fix SVG sources and rerender any defect.

- [ ] **Step 7: Commit assets**

~~~bash
git add tools/*/assets tests/assets.test.sh
git commit -m "design: add Node Trail brand assets"
~~~

---

### Task 8: Documentation

**Files:**

- Create: README.md
- Create: tools/cochat/README.md
- Create: tools/cosession/README.md
- Create: tools/cobox/README.md
- Modify: tests/assets.test.sh

**Interfaces:**

- Consumes: implemented commands, security boundaries, assets, versions, and URL.
- Produces: complete install, usage, internals, security, and troubleshooting docs.

- [ ] **Step 1: Add failing documentation assertions**

Require four README files and assert exact facts:

~~~text
README: curl -fsSL https://raw.githubusercontent.com/plabanauskis/cotools/main/install.sh | bash
README: not affiliated with or endorsed by OpenAI
cosession README: CODEX_HOME and $HOME/.codex
cobox README: --dangerously-bypass-approvals-and-sandbox
cobox README: never mounts the host Docker socket
~~~

Add a runtime/source audit rejecting old public names, Claude runtime terms, Anthropic auth, and #D97757 outside the approved spec/plan historical context. Exclude .git and .superpowers.

- [ ] **Step 2: Run and verify the expected failure**

~~~bash
bash tests/assets.test.sh
~~~

Expected: nonzero because README files do not exist.

- [ ] **Step 3: Write root README**

Port the source structure: hero assets/badges, tool table, curl and inspect-first installs, user-owned locations, uninstall order, manager examples, tool links, cobox threat-model summary, development/release instructions, MIT attribution, and independent/non-endorsement statement.

- [ ] **Step 4: Write cochat and cosession READMEs**

cochat covers retained temp dirs, argument pass-through, cosession resume, requirements, install, and examples.

cosession covers picker layout, CLI/Desktop inclusion, internal-agent exclusion, summary precedence, CODEX_HOME, rollout fields, live/gone behavior, GNU utilities, and tests.

- [ ] **Step 5: Write cobox README**

Document sysbox blast radius; npm/native host installs; Codex state/auth; build/doctor/uninstall; ports/caches/inner Docker/tint; absent host Docker socket/SSH/GitHub credentials; bypass flag inside external isolation; toolchains/amd64; and troubleshooting.

- [ ] **Step 6: Run docs and asset verification**

~~~bash
bash tests/assets.test.sh
~~~

Expected: required text, naming audit, XML, and PNG assertions pass.

- [ ] **Step 7: Commit documentation**

~~~bash
git add README.md tools/*/README.md tests/assets.test.sh
git commit -m "docs: document the cotools suite"
~~~

---

### Task 9: Full Verification and Parity Audit

**Files:**

- Modify only files implicated by an observed verification failure.
- Verify all files from Tasks 1–8.

**Interfaces:**

- Consumes: complete repository and design acceptance criteria.
- Produces: clean checks, clean Git state, and evidence-backed handoff.

- [ ] **Step 1: Run complete local check**

~~~bash
scripts/check.sh
~~~

Expected: check.sh: ALL CHECKS PASSED. cobox smoke may visibly skip only when image/sysbox is unavailable; syntax, lint, format, suites, assets, and docs pass.

- [ ] **Step 2: Exercise public surfaces**

~~~bash
bin/cotools help
bin/cotools version
tools/cochat/cochat --help
tools/cosession/cosession --help
tools/cobox/bin/cobox help
tools/cobox/bin/cobox version
~~~

Expected: zero exits, cotools/Codex naming, and 1.0.0 versions.

- [ ] **Step 3: Compare file structure with baseline**

List all target files excluding .git/.superpowers and all source files excluding source .git. Confirm every functional baseline component has a target counterpart. Design/spec/plan and asset test are intentional additions.

- [ ] **Step 4: Audit names and unsafe mounts**

Search runtime files for old uppercase variables, Anthropic auth, Claude permission flag/state, and ccbox resource prefix. Search cobox code for --privileged, docker.sock, and --network=host.

Expected: old names occur only in historical design/plan context; unsafe strings occur only in documentation statements that they are not used, never in Docker args.

- [ ] **Step 5: Inspect Git state and history**

~~~bash
git status --short
git remote -v
git log --oneline --decorate --max-count=12
~~~

Expected: clean tree, no remote, and readable task commits.

- [ ] **Step 6: Apply completion skills**

Invoke superpowers:verification-before-completion and rerun its required fresh evidence. Then invoke superpowers:requesting-code-review for an independent requirements/quality review and resolve every verified finding. Do not push or create a remote. Use finishing-a-development-branch only if the user later asks for integration options.
