#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIBOX="$HERE/../bin/pibox"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); }
fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}
assert_eq() {
  if [ "$1" = "$2" ]; then pass; else fail "$3\n  got:  [$1]\n  want: [$2]"; fi
}
assert_zero() {
  if [ "$1" -eq 0 ]; then pass; else fail "$2 (got exit $1, want 0)"; fi
}
assert_nonzero() {
  if [ "$1" -ne 0 ]; then pass; else fail "$2 (got exit 0, want nonzero)"; fi
}
assert_contains() {
  if [[ "$1" == *"$2"* ]]; then pass; else fail "$3\n  [$1] does not contain [$2]"; fi
}
assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then pass; else fail "$3\n  [$1] unexpectedly contains [$2]"; fi
}
assert_record_has() {
  local token
  for token in "${RECORDED[@]}"; do
    if [ "$token" = "$1" ]; then
      pass
      return
    fi
  done
  fail "$2\n  recorder has no literal token [$1]"
}
assert_record_lacks_fragment() {
  local token
  for token in "${RECORDED[@]}"; do
    if [[ "$token" == *"$1"* ]]; then
      fail "$2\n  recorder token [$token] contains forbidden fragment [$1]"
      return
    fi
  done
  pass
}
assert_record_sequence() {
  local mutation="$1"
  shift
  local start index expected matched
  for ((start = 0; start <= ${#RECORDED[@]} - $#; start++)); do
    matched=1
    index=0
    for expected in "$@"; do
      if [ "${RECORDED[start + index]}" != "$expected" ]; then
        matched=0
        break
      fi
      index=$((index + 1))
    done
    if [ "$matched" -eq 1 ]; then
      pass
      return
    fi
  done
  fail "$mutation\n  recorder does not contain the required consecutive token sequence"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
REAL_NODE="$(command -v node)"
NODE_BIN="$(dirname "$REAL_NODE")"

npm_pkg="$SANDBOX/npm/lib/node_modules/@earendil-works/pi-coding-agent"
mkdir -p "$npm_pkg/dist/bundle"
printf '{"name":"@earendil-works/pi-coding-agent","version":"9.9.9"}\n' >"$npm_pkg/package.json"
printf '#!/usr/bin/env node\n' >"$npm_pkg/dist/bundle/cli.js"
chmod +x "$npm_pkg/dist/bundle/cli.js"

binary_pkg="$SANDBOX/binary-pi"
mkdir -p "$binary_pkg"
printf '{"name":"@earendil-works/pi-coding-agent","version":"9.9.9"}\n' >"$binary_pkg/package.json"
printf '\177ELFfake-pi\n' >"$binary_pkg/pi"
chmod +x "$binary_pkg/pi"

unsupported="$SANDBOX/custom/pi"
mkdir -p "$(dirname "$unsupported")"
printf '#!/usr/bin/env bash\n' >"$unsupported"
chmod +x "$unsupported"

TEST_HOME="$SANDBOX/home"
PI_STATE="$SANDBOX/pi agent state"
REPO="$SANDBOX/project alpha"
mkdir -p "$TEST_HOME" "$PI_STATE" "$REPO"
printf '[user]\n  name = Test User\n' >"$TEST_HOME/.gitconfig"
git -C "$REPO" init -q

if [ ! -f "$PIBOX" ]; then
  fail "missing pibox entrypoint: $PIBOX"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 1
fi

export HOME="$TEST_HOME"
export PI_CODING_AGENT_DIR="$PI_STATE"
unset PI_CODING_AGENT_SESSION_DIR
# shellcheck source=../bin/pibox
# shellcheck disable=SC1091
source "$PIBOX"

# Resolver protocol: validate exact official npm and compiled Pi layouts.
resolved="$(resolve_pi_install "$npm_pkg/dist/bundle/cli.js")"
assert_eq "$resolved" "npm${SEP}$npm_pkg/dist/bundle/cli.js${SEP}$npm_pkg" \
  'resolve npm derives the official package mount'
resolved="$(resolve_pi_install "$binary_pkg/pi")"
assert_eq "$resolved" "binary${SEP}$binary_pkg/pi${SEP}$binary_pkg" \
  'resolve binary includes adjacent runtime assets in the read-only mount'

set +e
unsupported_out="$(resolve_pi_install "$unsupported" 2>&1)"
unsupported_rc=$?
set -e
assert_nonzero "$unsupported_rc" 'resolve rejects an arbitrary shebang script'
assert_contains "$unsupported_out" 'supported layouts' 'resolve script error explains supported layouts'
assert_contains "$unsupported_out" '@earendil-works/pi-coding-agent' 'resolve script error names current Pi package'

bad_pkg="$SANDBOX/bad/lib/node_modules/@earendil-works/pi-coding-agent"
mkdir -p "$bad_pkg/dist/bundle"
printf '{"name":"not-pi"}\n' >"$bad_pkg/package.json"
printf '#!/usr/bin/env node\n' >"$bad_pkg/dist/bundle/cli.js"
chmod +x "$bad_pkg/dist/bundle/cli.js"
set +e
bad_out="$(resolve_pi_install "$bad_pkg/dist/bundle/cli.js" 2>&1)"
bad_rc=$?
set -e
assert_nonzero "$bad_rc" 'resolve npm rejects counterfeit package metadata'
assert_contains "$bad_out" 'package.json' 'resolve npm identity failure identifies package.json'

multiline_pkg="$SANDBOX/multiline/lib/node_modules/@earendil-works/pi-coding-agent"
mkdir -p "$multiline_pkg/dist/bundle"
printf '{\n  "name"\n    :\n    "@earendil-works/pi-coding-agent"\n}\n' >"$multiline_pkg/package.json"
printf '#!/usr/bin/env node\n' >"$multiline_pkg/dist/bundle/cli.js"
chmod +x "$multiline_pkg/dist/bundle/cli.js"
assert_eq "$(resolve_pi_install "$multiline_pkg/dist/bundle/cli.js")" \
  "npm${SEP}$multiline_pkg/dist/bundle/cli.js${SEP}$multiline_pkg" \
  'resolve npm validates structurally formatted JSON'

# Fake Docker records literal argv tokens, observing mount modes, credentials,
# and Pi argument boundaries without requiring a daemon or image.
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
ln -s "$npm_pkg/dist/bundle/cli.js" "$BIN/pi"
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  info) printf '{io.containerd.runc.v2 sysbox-runc}\n' ;;
  image) [ "${FAKE_IMAGE_PRESENT:-1}" = 1 ] ;;
  run) printf '%s\n' "$@" >"$DOCKER_RECORD" ;;
  volume)
    case "${2:-}" in ls) exit 0 ;; *) exit 1 ;; esac
    ;;
  rmi) exit 0 ;;
  *) exit 0 ;;
esac
SH
chmod +x "$BIN/docker"

run_launch() {
  local record="$1"
  shift
  (
    cd "$REPO" || exit
    env \
      PATH="$BIN:$NODE_BIN:/usr/bin:/bin" \
      HOME="$TEST_HOME" \
      PI_CODING_AGENT_DIR="$PI_STATE" \
      DOCKER_RECORD="$record" \
      PIBOX_NO_TINT=1 \
      "$@" \
      "$PIBOX" --model "openai/gpt 5" "prompt with spaces"
  )
}

RECORD_NO_AUTH="$SANDBOX/docker-no-auth.args"
set +e
run_launch "$RECORD_NO_AUTH" env -u OPENAI_API_KEY -u ANTHROPIC_API_KEY >/dev/null 2>&1
launch_rc=$?
set -e
assert_zero "$launch_rc" 'launch does not gate on one particular authentication method'
mapfile -t RECORDED <"$RECORD_NO_AUTH"
assert_record_has '--runtime=sysbox-runc' 'launch isolation requires sysbox'
assert_record_sequence 'launch marker is present' -e 'PIBOX=1'
assert_record_sequence 'launch state environment uses path-identical agent dir' \
  -e "PI_CODING_AGENT_DIR=$PI_STATE"
assert_record_sequence 'launch suppresses in-box host-version checks' -e 'PI_SKIP_VERSION_CHECK=1'
assert_record_sequence 'launch project mount and workdir are path-identical' \
  -v "$REPO:$REPO" -w "$REPO"
assert_record_sequence 'launch Pi state is writable and persistent' -v "$PI_STATE:$PI_STATE"
assert_record_sequence 'launch npm installation is read-only' -v "$npm_pkg:$npm_pkg:ro"
assert_record_sequence 'launch Git identity is read-only' -v "$TEST_HOME/.gitconfig:$TEST_HOME/.gitconfig:ro"
assert_record_sequence 'launch inner-Docker data is project-specific' \
  -v 'pibox-docker-project_alpha:/var/lib/docker'
assert_record_sequence 'launch passes exact Pi argv without invented harness flags' \
  'pibox:latest' "$npm_pkg/dist/bundle/cli.js" --model 'openai/gpt 5' 'prompt with spaces'
assert_record_lacks_fragment 'dangerously-' 'Pi has no sandbox-bypass flag to inject'
assert_record_lacks_fragment 'docker.sock' 'host Docker socket must never be mounted'
assert_record_lacks_fragment '/.ssh' 'SSH credentials must never be mounted'
assert_record_lacks_fragment '/gh/' 'GitHub CLI credentials must never be mounted'
assert_record_lacks_fragment '--privileged' 'privileged mode breaks the boundary'
assert_record_lacks_fragment '--network=host' 'host networking exceeds the boundary'

RECORD_AUTH="$SANDBOX/docker-auth.args"
set +e
run_launch "$RECORD_AUTH" env OPENAI_API_KEY='api key value' ANTHROPIC_API_KEY='anthropic value' >/dev/null 2>&1
launch_auth_rc=$?
set -e
assert_zero "$launch_auth_rc" 'launch accepts supported provider credentials'
mapfile -t RECORDED <"$RECORD_AUTH"
assert_record_sequence 'OpenAI credential preserves argument boundary' -e 'OPENAI_API_KEY=api key value'
assert_record_sequence 'Anthropic credential preserves argument boundary' -e 'ANTHROPIC_API_KEY=anthropic value'

# A custom session directory outside agent state needs its own identical mount.
CUSTOM_SESSIONS="$SANDBOX/custom sessions"
mkdir -p "$CUSTOM_SESSIONS"
PI_SESSION_DIR="$CUSTOM_SESSIONS"
build_docker_args "$REPO" npm "$npm_pkg/dist/bundle/cli.js" "$npm_pkg"
RECORDED=("${DOCKER_ARGS[@]}")
assert_record_sequence 'custom session environment is preserved' \
  -e "PI_CODING_AGENT_SESSION_DIR=$CUSTOM_SESSIONS"
assert_record_sequence 'external custom sessions get a path-identical mount' \
  -v "$CUSTOM_SESSIONS:$CUSTOM_SESSIONS"
# shellcheck disable=SC2034 # consumed by sourced build_docker_args on later calls
PI_SESSION_DIR=''

# Compiled builds mount their complete asset directory, not only the binary.
build_docker_args "$REPO" binary "$binary_pkg/pi" "$binary_pkg"
RECORDED=("${DOCKER_ARGS[@]}")
assert_record_sequence 'compiled Pi runtime assets are read-only' -v "$binary_pkg:$binary_pkg:ro"

# Doctor reports auth readiness from mounted auth.json or allowlisted env vars.
printf '{}\n' >"$PI_STATE/auth.json"
set +e
doctor_out="$(PATH="$BIN:$NODE_BIN:/usr/bin:/bin" pibox_doctor 2>&1)"
doctor_rc=$?
set -e
assert_nonzero "$doctor_rc" 'doctor marks empty auth state unhealthy'
assert_contains "$doctor_out" 'auth' 'doctor identifies auth readiness check'
printf '{"anthropic":{"type":"api_key","key":"x"}}\n' >"$PI_STATE/auth.json"
set +e
doctor_auth_out="$(PATH="$BIN:$NODE_BIN:/usr/bin:/bin" pibox_doctor 2>&1)"
doctor_auth_rc=$?
set -e
assert_zero "$doctor_auth_rc" 'doctor accepts nonempty file-backed Pi auth state'
assert_contains "$doctor_auth_out" 'All good.' 'doctor reports complete readiness'

# Missing images and non-Git directories default to safe abort without a TTY.
if command -v setsid >/dev/null 2>&1; then
  set +e
  missing_image_out="$(
    cd "$REPO" || exit
    setsid -w env PATH="$BIN:$NODE_BIN:/usr/bin:/bin" HOME="$TEST_HOME" \
      PI_CODING_AGENT_DIR="$PI_STATE" DOCKER_RECORD="$SANDBOX/unused.args" \
      PIBOX_NO_TINT=1 FAKE_IMAGE_PRESENT=0 "$PIBOX" 2>&1
  )"
  missing_image_rc=$?
  set -e
  assert_nonzero "$missing_image_rc" 'missing image unattended launch safely aborts'
  assert_contains "$missing_image_out" 'pibox build' 'missing image gives recovery command'

  NOGIT="$SANDBOX/not-git"
  mkdir -p "$NOGIT"
  set +e
  nogit_out="$(
    cd "$NOGIT" || exit
    setsid -w env PATH="$BIN:$NODE_BIN:/usr/bin:/bin" HOME="$TEST_HOME" \
      PI_CODING_AGENT_DIR="$PI_STATE" DOCKER_RECORD="$SANDBOX/unused.args" \
      PIBOX_NO_TINT=1 "$PIBOX" 2>&1
  )"
  nogit_rc=$?
  set -e
  assert_nonzero "$nogit_rc" 'non-Git unattended launch safely aborts'
  assert_contains "$nogit_out" 'is not a git repository' 'non-Git warning names missing boundary'
  assert_contains "$nogit_out" 'NO undo' 'non-Git warning explains destructive risk'
else
  printf 'SKIP: setsid unavailable — unattended prompt tests skipped\n'
fi

# Build context follows the resolved launcher path, not a symlink directory.
BUILD_LINK_DIR="$SANDBOX/bin-link"
EMPTY_SHARE="$SANDBOX/empty-share"
BUILD_RECORD="$SANDBOX/docker-build.args"
mkdir -p "$BUILD_LINK_DIR" "$EMPTY_SHARE"
ln -s "$PIBOX" "$BUILD_LINK_DIR/pibox"
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$DOCKER_RECORD"
SH
chmod +x "$BIN/docker"
set +e
PATH="$BIN:$NODE_BIN:/usr/bin:/bin" HOME="$TEST_HOME" PIBOX_SHARE_DIR="$EMPTY_SHARE" \
  DOCKER_RECORD="$BUILD_RECORD" "$BUILD_LINK_DIR/pibox" build >/dev/null 2>&1
build_rc=$?
set -e
assert_zero "$build_rc" 'build resolves the real pibox Dockerfile through a launcher symlink'
if [ -f "$BUILD_RECORD" ]; then
  mapfile -t RECORDED <"$BUILD_RECORD"
  assert_eq "${RECORDED[1]:-}" '--file' 'build passes an explicit Dockerfile'
  assert_eq "${RECORDED[2]:-}" "$(readlink -f "$HERE/../Dockerfile")" \
    'build resolves the shared recipe outside the context for BuildKit'
  assert_eq "${RECORDED[${#RECORDED[@]} - 1]:-}" "$(cd "$HERE/.." && pwd)" \
    'build uses tools/pibox as its fallback context'
else
  fail 'build must invoke docker with a context directory'
fi

# Artifact contracts make accidental toolchain and embedding drift visible.
DOCKERFILE="$HERE/../Dockerfile"
if [ -f "$DOCKERFILE" ]; then
  dockerfile_text="$(<"$DOCKERFILE")"
  assert_contains "$dockerfile_text" 'ARG NODE_MAJOR=24' 'Dockerfile keeps Node 24'
  assert_contains "$dockerfile_text" 'ARG GO_VERSION=1.26.4' 'Dockerfile keeps Go 1.26.4'
  assert_contains "$dockerfile_text" 'ARG DOTNET_CHANNEL=10.0' 'Dockerfile keeps .NET 10'
  assert_not_contains "$dockerfile_text" '@earendil-works/pi-coding-agent' \
    'Dockerfile must not embed a second Pi installation'
  assert_contains "$dockerfile_text" '/etc/profile.d/agent-tools-toolchains.sh' \
    'Dockerfile keeps interactive toolchain paths'
else
  fail 'missing Dockerfile'
fi

# PIBOX_NO_DOCKER skips daemon checks/startup but still executes the command.
ENTRYPOINT="$HERE/../entrypoint.sh"
ENTRYPOINT_RECORD="$SANDBOX/entrypoint-docker.args"
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >>"$DOCKER_RECORD"
exit 0
SH
chmod +x "$BIN/docker"
set +e
entrypoint_out="$(PATH="$BIN:/usr/bin:/bin" DOCKER_RECORD="$ENTRYPOINT_RECORD" \
  PIBOX_NO_DOCKER=1 "$ENTRYPOINT" printf 'entrypoint command ran' 2>&1)"
entrypoint_rc=$?
set -e
assert_zero "$entrypoint_rc" 'entrypoint no-docker still executes command'
assert_eq "$entrypoint_out" 'entrypoint command ran' 'entrypoint preserves command stdout'
if [ -e "$ENTRYPOINT_RECORD" ]; then
  assert_eq "$(<"$ENTRYPOINT_RECORD")" '' 'entrypoint no-docker makes no Docker calls'
else
  pass
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
