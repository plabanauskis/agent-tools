#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COBOX="$HERE/../bin/cobox"

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL: %s\n' "$1"
}

assert_eq() { # <got> <want> <mutation>
  if [ "$1" = "$2" ]; then
    pass
  else
    fail "$3
  got:  [$1]
  want: [$2]"
  fi
}

assert_zero() { # <status> <mutation>
  if [ "$1" -eq 0 ]; then
    pass
  else
    fail "$2 (got exit $1, want 0)"
  fi
}

assert_nonzero() { # <status> <mutation>
  if [ "$1" -ne 0 ]; then
    pass
  else
    fail "$2 (got exit 0, want nonzero)"
  fi
}

assert_contains() { # <haystack> <needle> <mutation>
  if [[ "$1" == *"$2"* ]]; then
    pass
  else
    fail "$3
  [$1] does not contain [$2]"
  fi
}

assert_record_has() { # <literal token> <mutation>
  local token
  for token in "${RECORDED[@]}"; do
    if [ "$token" = "$1" ]; then
      pass
      return
    fi
  done
  fail "$2
  recorder has no literal token [$1]"
}

assert_record_lacks_fragment() { # <fragment> <mutation>
  local token
  for token in "${RECORDED[@]}"; do
    if [[ "$token" == *"$1"* ]]; then
      fail "$2
  recorder token [$token] contains forbidden fragment [$1]"
      return
    fi
  done
  pass
}

assert_record_sequence() { # <mutation> <token...>
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
  fail "$mutation
  recorder does not contain the required consecutive token sequence"
}

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

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

if [ ! -f "$COBOX" ]; then
  fail "missing cobox entrypoint: $COBOX"
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  exit 1
fi

# shellcheck source=../bin/cobox
# shellcheck disable=SC1091
source "$COBOX"

# Resolver protocol. Mutations caught: wrong install branch, path, mount source,
# package identity validation, or acceptance of an incomplete script install.
resolved="$(resolve_codex_install "$npm_pkg/bin/codex.js")"
assert_eq "$resolved" "npm${SEP}$npm_pkg/bin/codex.js${SEP}$npm_pkg" \
  "resolve npm: changing the official package-root derivation corrupts the emitted mount contract"

resolved="$(resolve_codex_install "$native")"
assert_eq "$resolved" "native${SEP}$native${SEP}$native" \
  "resolve native: treating a native executable as a package emits the wrong read-only mount"

set +e
unsupported_out="$(resolve_codex_install "$unsupported" 2>&1)"
unsupported_rc=$?
set -e
assert_nonzero "$unsupported_rc" \
  "resolve script: accepting an arbitrary shebang can mount an incomplete or hostile installation"
assert_contains "$unsupported_out" "supported" \
  "resolve script: an unsupported layout must explain that only supported layouts can launch"
assert_contains "$unsupported_out" "@openai/codex/bin/codex.js" \
  "resolve script: the error must identify the actionable official npm layout"
assert_contains "$unsupported_out" "native executable" \
  "resolve script: the error must identify the actionable native alternative"

bad_pkg="$SANDBOX/bad/lib/node_modules/@openai/codex"
mkdir -p "$bad_pkg/bin"
printf '{"name":"not-codex"}\n' >"$bad_pkg/package.json"
printf '#!/usr/bin/env node\n' >"$bad_pkg/bin/codex.js"
chmod +x "$bad_pkg/bin/codex.js"
set +e
bad_pkg_out="$(resolve_codex_install "$bad_pkg/bin/codex.js" 2>&1)"
bad_pkg_rc=$?
set -e
assert_nonzero "$bad_pkg_rc" \
  "resolve npm identity: trusting only a matching path admits a counterfeit package root"
assert_contains "$bad_pkg_out" "package.json" \
  "resolve npm identity: package verification failure must identify package.json"

# Fake external boundary. Docker records literal argv tokens, so mount modes,
# environment propagation, and Codex argument boundaries are observed exactly.
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
ln -s "$npm_pkg/bin/codex.js" "$BIN/codex"
cat >"$BIN/docker" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  info)
    printf '{io.containerd.runc.v2 sysbox-runc}\n'
    ;;
  image)
    [ "${FAKE_IMAGE_PRESENT:-1}" = "1" ]
    ;;
  run)
    printf '%s\n' "$@" >"$DOCKER_RECORD"
    ;;
  volume)
    case "${2:-}" in
      ls) exit 0 ;;
      *) exit 1 ;;
    esac
    ;;
  rmi)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
SH
cat >"$BIN/node" <<'SH'
#!/usr/bin/env bash
exit "${FAKE_CODEX_LOGIN_RC:-0}"
SH
chmod +x "$BIN/docker" "$BIN/node"

TEST_HOME="$SANDBOX/home"
CODEX_STATE="$SANDBOX/codex state"
REPO="$SANDBOX/project alpha"
mkdir -p "$TEST_HOME" "$CODEX_STATE" "$REPO"
printf '[user]\n  name = Test User\n' >"$TEST_HOME/.gitconfig"
git -C "$REPO" init -q
printf '4100\n' >"$REPO/.cobox-ports-placeholder"

run_launch() {
  local record="$1"
  shift
  (
    cd "$REPO" || exit
    env \
      PATH="$BIN:/usr/bin:/bin" \
      HOME="$TEST_HOME" \
      CODEX_HOME="$CODEX_STATE" \
      DOCKER_RECORD="$record" \
      COBOX_NO_TINT=1 \
      FAKE_CODEX_LOGIN_RC=1 \
      "$@" \
      "$COBOX" --model "gpt 5" "prompt with spaces"
  )
}

RECORD_NO_AUTH="$SANDBOX/docker-no-auth.args"
set +e
run_launch "$RECORD_NO_AUTH" env -u OPENAI_API_KEY -u CODEX_ACCESS_TOKEN >/dev/null 2>&1
launch_rc=$?
set -e
assert_zero "$launch_rc" \
  "launch auth gate: checking codex login status during launch blocks alternate valid authentication"
mapfile -t RECORDED <"$RECORD_NO_AUTH"

assert_record_has "--runtime=sysbox-runc" \
  "launch isolation: removing sysbox exposes the host to the in-box sandbox bypass"
assert_record_sequence "launch marker: changing the in-box marker breaks sandbox detection" \
  -e "COBOX=1"
assert_record_sequence "launch state env: omitting CODEX_HOME makes Codex use a different state root" \
  -e "CODEX_HOME=$CODEX_STATE"
assert_record_sequence "launch project: changing the mount or workdir breaks path-identical project access" \
  -v "$REPO:$REPO" -w "$REPO"
assert_record_sequence "launch state: changing the mount loses persistent auth/config/session writes" \
  -v "$CODEX_STATE:$CODEX_STATE"
assert_record_sequence "launch npm: dropping :ro lets the agent overwrite the host Codex package" \
  -v "$npm_pkg:$npm_pkg:ro"
assert_record_sequence "launch git identity: dropping :ro lets the agent overwrite host Git config" \
  -v "$TEST_HOME/.gitconfig:$TEST_HOME/.gitconfig:ro"
assert_record_sequence "launch data: changing the project volume loses inner-Docker persistence" \
  -v "cobox-docker-project_alpha:/var/lib/docker"
assert_record_sequence "launch argv: changing command ordering, bypass flag, or quoting alters requested Codex behavior" \
  "cobox:latest" "$npm_pkg/bin/codex.js" --dangerously-bypass-approvals-and-sandbox \
  --model "gpt 5" "prompt with spaces"
assert_record_lacks_fragment "OPENAI_API_KEY" \
  "launch auth env: exporting an unset API key changes Codex authentication precedence"
assert_record_lacks_fragment "CODEX_ACCESS_TOKEN" \
  "launch auth env: exporting an unset access token changes Codex authentication precedence"
assert_record_lacks_fragment "docker.sock" \
  "launch security: mounting the host Docker socket gives the agent host-root control"
assert_record_lacks_fragment "/.ssh" \
  "launch security: mounting SSH credentials gives the agent unapproved remote access"
assert_record_lacks_fragment "/gh/" \
  "launch security: mounting GitHub CLI credentials gives the agent push/API credentials"
assert_record_lacks_fragment "--privileged" \
  "launch security: privileged mode breaks the sysbox threat boundary"
assert_record_lacks_fragment "--network=host" \
  "launch security: host networking exceeds the documented boundary"

RECORD_AUTH="$SANDBOX/docker-auth.args"
set +e
run_launch "$RECORD_AUTH" env OPENAI_API_KEY="api key value" CODEX_ACCESS_TOKEN="token value" >/dev/null 2>&1
launch_auth_rc=$?
set -e
assert_zero "$launch_auth_rc" \
  "launch optional auth: supplied host authentication must not prevent launch"
mapfile -t RECORDED <"$RECORD_AUTH"
assert_record_sequence "launch API auth: splitting or omitting the value breaks API-key login" \
  -e "OPENAI_API_KEY=api key value"
assert_record_sequence "launch token auth: splitting or omitting the value breaks token login" \
  -e "CODEX_ACCESS_TOKEN=token value"

# Direct Docker-argument contract for a native executable. This complements the
# npm launch recorder and catches using the npm package root for every install.
HOME="$TEST_HOME" CODEX_HOME="$CODEX_STATE" build_docker_args \
  "$REPO" native "$native" "$native"
RECORDED=("${DOCKER_ARGS[@]}")
assert_record_sequence "native mount: omitting :ro lets the agent replace the exact host executable" \
  -v "$native:$native:ro"

# Doctor owns login health reporting; launch deliberately does not.
set +e
doctor_out="$(
  PATH="$BIN:/usr/bin:/bin" \
    HOME="$TEST_HOME" \
    CODEX_HOME="$CODEX_STATE" \
    FAKE_CODEX_LOGIN_RC=1 \
    cobox_doctor 2>&1
)"
doctor_rc=$?
set -e
assert_nonzero "$doctor_rc" \
  "doctor login: hiding a failed codex login status reports a healthy installation"
assert_contains "$doctor_out" "login" \
  "doctor login: failure output must identify the unhealthy login check"
assert_contains "$doctor_out" "MISSING" \
  "doctor login: failed login status must be visibly unhealthy"

# Missing images and non-Git directories default to safe abort without a TTY.
if command -v setsid >/dev/null 2>&1; then
  set +e
  missing_image_out="$(
    cd "$REPO" || exit
    setsid -w env \
      PATH="$BIN:/usr/bin:/bin" \
      HOME="$TEST_HOME" \
      CODEX_HOME="$CODEX_STATE" \
      DOCKER_RECORD="$SANDBOX/unused.args" \
      COBOX_NO_TINT=1 \
      FAKE_IMAGE_PRESENT=0 \
      "$COBOX" 2>&1
  )"
  missing_image_rc=$?
  set -e
  assert_nonzero "$missing_image_rc" \
    "missing image: unattended launch must not silently build or continue"
  assert_contains "$missing_image_out" "cobox build" \
    "missing image: declined build must provide the exact recovery command"

  NOGIT="$SANDBOX/not-git"
  mkdir -p "$NOGIT"
  set +e
  nogit_out="$(
    cd "$NOGIT" || exit
    setsid -w env \
      PATH="$BIN:/usr/bin:/bin" \
      HOME="$TEST_HOME" \
      CODEX_HOME="$CODEX_STATE" \
      DOCKER_RECORD="$SANDBOX/unused.args" \
      COBOX_NO_TINT=1 \
      "$COBOX" 2>&1
  )"
  nogit_rc=$?
  set -e
  assert_nonzero "$nogit_rc" \
    "non-Git gate: unattended launch must not grant autonomous write access without undo"
  assert_contains "$nogit_out" "is not a git repository" \
    "non-Git gate: warning must name the missing Git safety boundary"
  assert_contains "$nogit_out" "NO undo" \
    "non-Git gate: warning must explain that destructive edits cannot be recovered"
else
  printf 'SKIP: setsid unavailable — unattended prompt tests skipped\n'
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
