#!/usr/bin/env bash
# Regression test for Dockerfile/build-context resolution.
#
# When cctools enables ccbox it symlinks the command into ~/.local/bin, so the
# script is invoked through a symlink. find_share_dir() locates the Dockerfile
# relative to the script, which only works if SCRIPT_DIR dereferences the
# symlink to the real bundle path. We invoke ccbox through a symlink with a
# stubbed `docker` and assert `build` finds the Dockerfile rather than failing
# with "cannot find Dockerfile".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CCBOX="$(readlink -f "$HERE/../bin/ccbox")"   # absolute path to the real script
CCBOX_DIR="$(cd "$HERE/.." && pwd)"            # tools/ccbox — where the Dockerfile lives

PASS=0
FAIL=0
assert_contains() { # <haystack> <needle> <msg>
  if [[ "$1" == *"$2"* ]]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  [%s] does not contain [%s]\n' "$3" "$1" "$2"
  fi
}
refute_contains() { # <haystack> <needle> <msg>
  if [[ "$1" != *"$2"* ]]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  [%s] unexpectedly contains [%s]\n' "$3" "$1" "$2"
  fi
}
assert_eq() { # <got> <want> <msg>
  if [ "$1" = "$2" ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  got:  [%s]\n  want: [%s]\n' "$3" "$1" "$2"
  fi
}
assert_nonzero() { # <rc> <msg>
  if [ "$1" -ne 0 ]; then PASS=$((PASS + 1)); else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n  expected non-zero exit, got 0\n' "$2"
  fi
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
BIN="$SANDBOX/bin"
mkdir -p "$BIN" "$SANDBOX/empty-share"
# Reproduce the install: ccbox reached through a symlink in a different dir.
ln -s "$CCBOX" "$BIN/ccbox"
# Stub docker so `ccbox build` never runs a real (5GB) build; succeed for any args.
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$BIN/docker"

# CCBOX_SHARE_DIR points at an empty dir so the first search path deterministically
# misses (independent of whether /usr/share/ccbox exists). The Dockerfile can then
# only be found if SCRIPT_DIR resolved the symlink to the real bundle path.
run_build() { CCBOX_SHARE_DIR="$SANDBOX/empty-share" PATH="$BIN:$PATH" "$1" build 2>&1; }

# --- invoked through the symlink (the cctools install case) ---
out="$(run_build "$BIN/ccbox")"; rc=$?
assert_eq "$rc" "0" "build via symlink: exits 0 (Dockerfile resolved)"
refute_contains "$out" "cannot find Dockerfile" "build via symlink: no resolution error"
assert_contains "$out" "from $CCBOX_DIR" "build via symlink: resolves to the real bundle dir"

# --- invoked directly (run-from-clone case still works) ---
out_direct="$(run_build "$CCBOX")"; rc_direct=$?
assert_eq "$rc_direct" "0" "build run directly: exits 0 (Dockerfile resolved)"
refute_contains "$out_direct" "cannot find Dockerfile" "build run directly: no resolution error"

# --- launch gate: non-git dir warns + aborts unattended; git dir proceeds (no warning) ---
# Exercises the path that replaced the old hard "not inside a git repository" abort. Run under
# setsid so there is no controlling TTY: the launcher's `read … </dev/tty || ans=n` then
# deterministically defaults to abort instead of blocking on input.
if command -v setsid >/dev/null 2>&1; then
  # non-git: a fresh temp dir (and its parents) are not a git repo.
  NOGIT="$(mktemp -d)"
  out_nogit="$(cd "$NOGIT" && setsid -w env PATH="$BIN:$PATH" "$BIN/ccbox" 2>&1)"; rc_nogit=$?
  rm -rf "$NOGIT"
  assert_contains "$out_nogit" "is not a git repository" "non-git: warns it is not a git repo"
  assert_contains "$out_nogit" "NO undo" "non-git: warns the agent's edits have no undo"
  assert_nonzero "$rc_nogit" "non-git: aborts when unattended (no TTY -> default no)"
  refute_contains "$out_nogit" "sysbox" "non-git: stops at the prompt, never reaches the sysbox check"

  # git repo: gate passes, launch proceeds to the existing sysbox check (stub docker lacks it).
  GITDIR="$(mktemp -d)"
  git -C "$GITDIR" init -q
  out_git="$(cd "$GITDIR" && setsid -w env PATH="$BIN:$PATH" "$BIN/ccbox" 2>&1)"
  rm -rf "$GITDIR"
  refute_contains "$out_git" "is not a git repository" "git repo: no non-git warning"
  assert_contains "$out_git" "sysbox runtime not found" "git repo: proceeds to the sysbox check as before"
else
  printf 'SKIP: setsid unavailable — launch-gate tty tests skipped\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
