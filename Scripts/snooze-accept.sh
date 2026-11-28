#!/usr/bin/env bash
# Scripts/snooze-accept.sh -- isolated Mac wake-notice acceptance harness.
#
# Runs on the Mac. Root: /tmp/bob-wake-accept (vault, state, evidence, PID
# files). The scratch app bundle lives outside every temp dir at
# "$HOME/Library/Application Support/bob-wake-accept/<name>.app": usernoted
# refuses notification clients whose bundle LaunchServices flags
# `in-temp-dir` (/private/tmp, /private/var/folders). Every subcommand
# prints one JSON line on stdout; human diagnostics go to stderr. Exit 0
# on success, non-zero with {"ok":false,...} (or an error line) on failure.
#
# The scratch app gets its own bundle ID (org.bobs.bob-mac-capture.accept),
# its own defaults domain, disabled hotkeys, XDG state, and a disposable
# vault, so production Bob Mac Capture is never disturbed. Kill scratch
# processes only by the recorded PIDs, never by name or bundle ID.
#
# Subcommands:
#   up [--sha SHA]     build + install + launch the scratch app, start the
#                      signpost stream, run guard
#   rebuild --sha SHA  stop the scratch app by PID, rebuild and re-sign at
#                      the same path and bundle ID, relaunch, wait for claim
#   guard              assert production is untouched and scratch is healthy
#   wake SLUG TITLE [--channel auto|desktop|off]
#                      add a task to the disposable vault and wake it now
#   ping               post the org.bobs.bob.snooze.woken Darwin notification
#   probe COMMAND [ARGS...]
#                      write a probe request, ping Darwin, print the response
#   idle               HID idle seconds, lock, display sleep, pmset assertions
#   evidence --since T save log show --signpost for the scratch PID
#   shim passthrough|oldbob|off
#                      set bobExecutableOverride to an argv-logging shim
#   variant noauth|accept
#                      bring up accept-noauth (never authorized) or restore
#   lockwatch          lock-accept driver (foreground JSON lines)
#   stop               stop the scratch app and the signpost stream by PID
#   restart            stop, then relaunch the way up did
#   status             PIDs, claim, latest receipt, recent snooze signposts
#   down               stop everything, unregister, delete the accept domain
#                      and remove the root
#
# Production guardrails: never write to, kill, or relaunch
# ~/Applications/Bob Mac Capture.app, the org.bobs.bob-mac-capture defaults
# domain, ~/bob, ~/.local/state/bob-cli, or Bryan's checkout. Never run
# just install or just install-all. Run guard before and after every check.

set -euo pipefail

ROOT="/tmp/bob-wake-accept"
ACCEPT_ID="org.bobs.bob-mac-capture.accept"
ACCEPT_NAME="Bob Mac Capture Accept"
NOAUTH_ID="org.bobs.bob-mac-capture.accept-noauth"
NOAUTH_NAME="Bob Mac Capture Accept Noauth"
PROD_ID="org.bobs.bob-mac-capture"
WOKEN_KEY="org.bobs.bob.snooze.woken"
PROBE_KEY="org.bobs.bob-mac-capture.accept.probe"
SUBSYSTEM="org.bobs.bob-mac-capture"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

SRC_DIR="$ROOT/src"
VAULT_DIR="$ROOT/vault"
STATE_DIR="$ROOT/state"
EVIDENCE_DIR="$ROOT/evidence"
CONFIG_FILE="$ROOT/bob-config.yml"
SCRATCH_APP_DIR="$HOME/Library/Application Support/bob-wake-accept"
SCRATCH_APP="$SCRATCH_APP_DIR/$ACCEPT_NAME.app"
PROD_PID_FILE="$ROOT/production.pid"
SCRATCH_PID_FILE="$ROOT/scratch.pid"
STREAM_PID_FILE="$ROOT/signpost.pid"
SIGNPOST_LOG="$EVIDENCE_DIR/signposts.log"
HARNESS_SHA_FILE="$ROOT/harness-sha"

usage() {
    cat <<'EOF'
Usage: Scripts/snooze-accept.sh <up|rebuild|guard|wake|ping|probe|idle|evidence|shim|variant|lockwatch|stop|restart|status|down> [...]

  up [--sha SHA]     Build the scratch app at SHA (default: source checkout
                     HEAD), launch it isolated, start the signpost stream.
  rebuild --sha SHA  Stop by PID, rebuild and re-sign in place, relaunch.
  guard              Verify production is untouched and scratch is healthy.
  wake SLUG TITLE [--channel auto|desktop|off]
                     Add jobs:SLUG to the disposable vault and wake it now.
  ping               Post the woken Darwin notification.
  probe COMMAND [ARGS...]
                     Drive the in-app probe and print the response JSON.
  idle               HID idle, lock, display sleep, pmset assertions.
  evidence --since T Save signposts for the scratch PID since T.
  shim passthrough|oldbob|off
                     Point bobExecutableOverride at an argv-logging shim.
  variant noauth|accept
                     Switch the only scratch instance to accept-noauth or back.
  lockwatch          Foreground lock-accept driver; prints JSON result lines.
  stop               Stop the scratch app and stream by recorded PID.
  restart            stop, then relaunch the way up did.
  status             PIDs, claim, latest receipt, recent snooze signposts.
  down               Stop everything and remove the root and accept domain.
EOF
}

die() {
    printf 'snooze-accept: %s\n' "$*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# jstr prints its argument as a JSON string (with quotes).
jstr() {
    python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1]))' "$1"
}

mac_only() {
    [ "$(uname -s)" = "Darwin" ] || die "must run on the Mac (Darwin)"
}

script_repo_root() {
    (cd -- "$(dirname -- "$0")/.." && pwd -P)
}

# PIDs whose full command line contains the fixed string $1, one per line.
pids_matching() {
    pgrep -f "$1" 2>/dev/null || true
}

find_prod_pid() {
    # Production binary lives under ~/Applications; the scratch copy lives
    # under the app-support dir, so this pattern never matches scratch.
    pids_matching "Applications/Bob Mac Capture.app/Contents/MacOS/BobMacCapture"
}

find_scratch_pids() {
    # Matches any scratch bundle under the app-support dir (accept and
    # accept-noauth); never matches ~/Applications production.
    pids_matching "bob-wake-accept/"
}

load_variant() {
    local variant="accept"
    if [ -f "$ROOT/variant" ]; then
        variant="$(cat "$ROOT/variant")"
    fi
    case "$variant" in
        noauth)
            ACCEPT_ID="$NOAUTH_ID"
            ACCEPT_NAME="$NOAUTH_NAME"
            ;;
        *)
            ACCEPT_ID="org.bobs.bob-mac-capture.accept"
            ACCEPT_NAME="Bob Mac Capture Accept"
            ;;
    esac
    SCRATCH_APP="$SCRATCH_APP_DIR/$ACCEPT_NAME.app"
}

probe_dir() {
    printf '%s\n' "$STATE_DIR/bob-mac-capture-accept/probe"
}

scratch_env() {
    export BOB_DIR="$VAULT_DIR"
    export XDG_STATE_HOME="$STATE_DIR"
    export BOB_CONFIG_FILE="$CONFIG_FILE"
}

check_notification_client() {
    # Poll usernoted's log for this harness's accept client: accepted
    # ("Connection <id> with path:") or rejected ("Failed to find or
    # validate client of identifier <id>"). Saves the matching lines to
    # the evidence log. Prints accepted|unknown on stdout; dies loudly on
    # rejection, naming the bundle path and the in-temp-dir cause.
    local waited=0 output=""
    mkdir -p "$EVIDENCE_DIR"
    while [ "$waited" -lt 30 ]; do
        output="$(/usr/bin/log show --last 2m --style compact \
            --predicate "process == \"usernoted\" AND eventMessage CONTAINS \"$ACCEPT_ID\"" \
            2>/dev/null)" || output=""
        if printf '%s' "$output" | grep -q "Failed to find or validate client of identifier $ACCEPT_ID"; then
            printf '%s\n' "$output" >"$EVIDENCE_DIR/usernoted-client.log"
            die "usernoted refused client $ACCEPT_ID at $SCRATCH_APP (bundle flagged in-temp-dir)"
        fi
        if printf '%s' "$output" | grep -q "Connection $ACCEPT_ID with path:"; then
            printf '%s\n' "$output" >"$EVIDENCE_DIR/usernoted-client.log"
            printf 'accepted\n'
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    printf '%s\n' "$output" >"$EVIDENCE_DIR/usernoted-client.log"
    printf 'snooze-accept: no usernoted verdict for %s in the last 2m; recording unknown\n' \
        "$ACCEPT_ID" >&2
    printf 'unknown\n'
}

write_channel_config() {
    local channel="$1"
    case "$channel" in
        auto | desktop | off) ;;
        *) die "channel must be auto, desktop, or off (got $channel)" ;;
    esac
    {
        printf 'timezone: America/New_York\n'
        printf 'snooze:\n  notify: %s\n' "$channel"
    } >"$CONFIG_FILE"
}

ensure_vault() {
    local year datestr file
    year="$(date +%Y)"
    datestr="$(date +%F)"
    file="$(date +%Y%m%d)"
    mkdir -p "$VAULT_DIR/$year"
    mkdir -p "$VAULT_DIR/.obsidian/plugins/obsidian-tasks-plugin"
    if [ ! -f "$VAULT_DIR/bob.yml" ]; then
        printf 'timezone: America/New_York\n' >"$VAULT_DIR/bob.yml"
    fi
    if [ ! -f "$VAULT_DIR/jobs.md" ]; then
        printf -- '- [ ] #task Harness seed ^seed\n' >"$VAULT_DIR/jobs.md"
    fi
    if [ ! -f "$VAULT_DIR/$year/$file.md" ]; then
        {
            printf '# %s\n\n' "$datestr"
            printf '## Pomodoros\n\n## Tasks\n'
        } >"$VAULT_DIR/$year/$file.md"
    fi
    if [ ! -f "$VAULT_DIR/.obsidian/plugins/obsidian-tasks-plugin/data.json" ]; then
        cat >"$VAULT_DIR/.obsidian/plugins/obsidian-tasks-plugin/data.json" <<'EOF'
{"globalFilter":"#task","statusSettings":{"coreStatuses":[{"symbol":" ","name":"Todo","type":"TODO"},{"symbol":"x","name":"Done","type":"DONE"}],"customStatuses":[{"symbol":"/","name":"In Progress","type":"IN_PROGRESS"},{"symbol":"*","name":"Next","type":"ON_HOLD"},{"symbol":"?","name":"Blocked","type":"ON_HOLD"},{"symbol":"-","name":"Canceled","type":"CANCELLED"}]}}
EOF
    fi
}

# json_field FILE KEY prints the JSON value at KEY, or empty on any error.
json_field() {
    python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))
except Exception:
    print("")' "$1" "$2" 2>/dev/null
}

wait_for_pid_match() {
    # wait_for_pid_match EXPECTED_COUNT PATTERN TIMEOUT_S: poll until the
    # PID count for PATTERN equals EXPECTED_COUNT.
    local expected="$1" pattern="$2" timeout_s="$3" waited count
    waited=0
    while [ "$waited" -lt "$timeout_s" ]; do
        count="$(pids_matching "$pattern" | wc -l | tr -d ' ')"
        if [ "$count" = "$expected" ]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

wait_for_claim_pid() {
    # wait_for_claim_pid STATE_DIR PID TIMEOUT_S: poll until the notifier
    # claim at STATE_DIR names PID.
    local state_dir="$1" pid="$2" timeout_s="$3" waited claim
    waited=0
    while [ "$waited" -lt "$timeout_s" ]; do
        claim="$(json_field "$state_dir/bob-cli/snooze/notifier.json" pid)"
        if [ "$claim" = "$pid" ]; then
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

stop_pid() {
    # stop_pid PIDFILE [SIGNAL_WAIT_S]: SIGTERM the recorded PID, then
    # SIGKILL after the wait. Missing or dead PIDs are success.
    local pidfile="$1" wait_s="${2:-10}" pid waited
    [ -f "$pidfile" ] || return 0
    pid="$(cat "$pidfile")"
    case "$pid" in
        '' | *[!0-9]*) return 0 ;;
    esac
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    kill "$pid" 2>/dev/null || true
    waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$wait_s" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    return 0
}

launch_scratch() {
    # Launch the scratch app isolated: XDG state plus BOB_DIR only. Prints
    # the scratch PID on stdout.
    local scratch_pid
    if open -n -g -a "$SCRATCH_APP" \
        --env "XDG_STATE_HOME=$STATE_DIR" \
        --env "BOB_DIR=$VAULT_DIR" 2>/dev/null; then
        :
    else
        printf 'snooze-accept: open --env unavailable, executing binary directly\n' >&2
        mkdir -p "$EVIDENCE_DIR"
        nohup /usr/bin/env "XDG_STATE_HOME=$STATE_DIR" "BOB_DIR=$VAULT_DIR" \
            "$SCRATCH_APP/Contents/MacOS/BobMacCapture" \
            >>"$EVIDENCE_DIR/app.stdout.log" 2>&1 &
    fi
    wait_for_pid_match 1 "bob-wake-accept/" 25 \
        || die "scratch app did not reach exactly one process"
    scratch_pid="$(find_scratch_pids | head -n 1)"
    ps -E -p "$scratch_pid" 2>/dev/null | grep -q "XDG_STATE_HOME=$STATE_DIR" \
        || die "scratch pid $scratch_pid is missing the harness environment"
    printf '%s' "$scratch_pid" >"$SCRATCH_PID_FILE"
    wait_for_claim_pid "$STATE_DIR" "$scratch_pid" 25 \
        || die "scratch claim never named pid $scratch_pid"
    printf '%s\n' "$scratch_pid"
}

start_stream() {
    # start_stream PID: stream signposts for PID into the evidence log.
    local pid="$1"
    mkdir -p "$EVIDENCE_DIR"
    touch "$SIGNPOST_LOG"
    nohup /usr/bin/log stream --signpost --style compact \
        --predicate "subsystem == \"$SUBSYSTEM\" AND processIdentifier == $pid" \
        >>"$SIGNPOST_LOG" 2>&1 &
    printf '%s' "$!" >"$STREAM_PID_FILE"
    sleep 2
    kill -0 "$(cat "$STREAM_PID_FILE")" 2>/dev/null \
        || die "signpost stream died immediately"
}

stop_stream() {
    stop_pid "$STREAM_PID_FILE" 5
}

do_up() {
    local sha="" src_repo src_sha dirty src_bundle plist_id notification_client
    mac_only
    need git
    need rsync
    need python3
    need defaults
    [ -x /usr/libexec/PlistBuddy ] || die "missing required command: PlistBuddy"
    need open
    need notifyutil
    command -v bob >/dev/null 2>&1 || die "missing required command: bob"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --sha)
                sha="${2:?missing --sha value}"
                shift 2
                ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                die "up: unexpected argument $1"
                ;;
        esac
    done
    if [ -e "$ROOT" ]; then
        die "root $ROOT exists; run down first"
    fi
    if [ -e "$SCRATCH_APP_DIR" ]; then
        die "app dir $SCRATCH_APP_DIR exists; run down first"
    fi
    src_repo="$(script_repo_root)"
    if [ -z "$sha" ]; then
        [ -d "$src_repo/.git" ] || die "no --sha given and $src_repo is not a git checkout"
        sha="$(git -C "$src_repo" rev-parse HEAD)"
    fi
    if [ -d "$src_repo/.git" ]; then
        src_sha="$(git -C "$src_repo" rev-parse HEAD)"
        dirty="$(git -C "$src_repo" status --porcelain | head -n 5)"
        [ "$src_sha" = "$sha" ] || die "source checkout is $src_sha, not requested $sha"
    else
        dirty=""
    fi
    mkdir -p "$SRC_DIR" "$VAULT_DIR" "$STATE_DIR" "$EVIDENCE_DIR" "$SCRATCH_APP_DIR"
    rsync -a --delete --exclude .build --exclude .git "$src_repo/" "$SRC_DIR/"
    (cd "$SRC_DIR" && ./Scripts/bundle.sh --identity - >/dev/null) \
        || die "bundle.sh failed"
    src_bundle="$SRC_DIR/.build/bundle/Bob Mac Capture.app"
    [ -d "$src_bundle" ] || die "bundle missing at $src_bundle"
    rm -rf "$SCRATCH_APP"
    cp -R "$src_bundle" "$SCRATCH_APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ACCEPT_ID" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy bundle id failed"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $ACCEPT_NAME" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy bundle name failed"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $ACCEPT_NAME" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy display name failed"
    plist_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$SCRATCH_APP/Contents/Info.plist")" || die "PlistBuddy print failed"
    [ "$plist_id" = "$ACCEPT_ID" ] || die "bundle id is $plist_id, not $ACCEPT_ID"
    /usr/bin/codesign --force --deep --sign - "$SCRATCH_APP" \
        || die "ad-hoc sign failed"
    /usr/bin/codesign --verify --deep --strict "$SCRATCH_APP" \
        || die "codesign verify failed"
    # Record production before touching anything scratch.
    prod_pid="$(find_prod_pid | head -n 1)"
    [ -n "${prod_pid:-}" ] || die "production app is not running; start it first"
    kill -0 "$prod_pid" 2>/dev/null || die "production pid $prod_pid is dead"
    printf '%s' "$prod_pid" >"$PROD_PID_FILE"
    if [ -f "$HOME/.local/state/bob-cli/snooze/notifier.json" ]; then
        cp "$HOME/.local/state/bob-cli/snooze/notifier.json" "$ROOT/production-claim.json"
    fi
    # Seed only the accept domain. The production domain is never written.
    printf 'accept\n' >"$ROOT/variant"
    defaults write "$ACCEPT_ID" bobDirectory -string "$VAULT_DIR"
    defaults write "$ACCEPT_ID" useProductionHotkey -bool false
    defaults write "$ACCEPT_ID" captureAliasHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" refsHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" refsAliasHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" snoozeAcceptanceProbe -bool true
    ensure_vault
    write_channel_config auto
    scratch_env
    confirm_out="$(bob snooze -f json 2>"$EVIDENCE_DIR/confirm.err")" \
        || die "bob snooze -f json failed: $(cat "$EVIDENCE_DIR/confirm.err")"
    printf '%s' "$confirm_out" >"$EVIDENCE_DIR/confirm.json"
    python3 - "$VAULT_DIR" <<'EOF' || die "vault confirm failed: version or root mismatch"
import json, os, sys
report = json.load(open(os.environ.get("HARNESS_CONFIRM", "/tmp/bob-wake-accept/evidence/confirm.json")))
assert report.get("wake_notice_version") == 1, report
vault = os.path.realpath(sys.argv[1])
assert os.path.realpath(report["vault_root"]) == vault, report
EOF
    printf '%s' "$sha" >"$HARNESS_SHA_FILE"
    scratch_pid="$(launch_scratch)"
    start_stream "$scratch_pid"
    notification_client="$(check_notification_client)"
    do_guard >/dev/null || die "guard failed right after up; see guard output"
    printf '{"status":"up","sha":%s,"dirty":%s,"production_pid":%s,"scratch_pid":%s,"vault":%s,"bundle_id":%s,"scratch_app":%s,"notification_client":%s}\n' \
        "$(jstr "$sha")" \
        "$(if [ -n "${dirty:-}" ]; then printf 'true'; else printf 'false'; fi)" \
        "$prod_pid" "$scratch_pid" "$(jstr "$VAULT_DIR")" "$(jstr "$ACCEPT_ID")" \
        "$(jstr "$SCRATCH_APP")" "$(jstr "$notification_client")"
}

do_guard() {
    # Assert production is untouched and scratch is healthy. Prints one
    # JSON line with ok true/false; exits 1 when not ok.
    mac_only
    load_variant
    local ok="true" reason="" rec_prod now_prod prod_claim scratch_pid
    local scratch_count scratch_claim stream_pid scratch_real
    reason_init() { reason="$1"; ok="false"; }
    if [ ! -f "$PROD_PID_FILE" ]; then
        printf '{"ok":false,"reason":%s}\n' "$(jstr "no harness: $PROD_PID_FILE missing")"
        return 1
    fi
    rec_prod="$(cat "$PROD_PID_FILE")"
    if ! kill -0 "$rec_prod" 2>/dev/null; then
        printf '{"ok":false,"reason":%s,"production_pid":%s}\n' \
            "$(jstr "recorded production pid $rec_prod is dead")" "$rec_prod"
        return 1
    fi
    now_prod="$(find_prod_pid | head -n 1)"
    if [ "$now_prod" != "$rec_prod" ]; then
        reason_init "production pid changed (recorded $rec_prod, now ${now_prod:-none})"
    fi
    prod_claim="$(json_field "$HOME/.local/state/bob-cli/snooze/notifier.json" pid)"
    if [ "$prod_claim" != "$rec_prod" ]; then
        reason_init "production notifier names '${prod_claim:-none}', not $rec_prod"
    fi
    if defaults read "$PROD_ID" bobDirectory >/dev/null 2>&1; then
        reason_init "production domain $PROD_ID has bobDirectory (leak)"
    fi
    if [ ! -f "$SCRATCH_PID_FILE" ]; then
        reason_init "scratch pid file missing"
        scratch_pid=""
    else
        scratch_pid="$(cat "$SCRATCH_PID_FILE")"
        if ! kill -0 "$scratch_pid" 2>/dev/null; then
            reason_init "recorded scratch pid $scratch_pid is dead"
        fi
    fi
    scratch_count="$(find_scratch_pids | wc -l | tr -d ' ')"
    if [ "$scratch_count" != "1" ]; then
        reason_init "expected exactly one scratch process, found $scratch_count"
    elif [ -n "${scratch_pid:-}" ]; then
        if [ "$(find_scratch_pids | head -n 1)" != "$scratch_pid" ]; then
            reason_init "running scratch pid differs from recorded $scratch_pid"
        fi
    fi
    scratch_claim="$(json_field "$STATE_DIR/bob-cli/snooze/notifier.json" pid)"
    if [ -n "${scratch_pid:-}" ] && [ "$scratch_claim" != "$scratch_pid" ]; then
        reason_init "scratch notifier names '${scratch_claim:-none}', not $scratch_pid"
    fi
    if [ -e "$SCRATCH_APP" ]; then
        scratch_real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' \
            "$SCRATCH_APP" 2>/dev/null)" || scratch_real=""
        case "$scratch_real" in
            /private/tmp/* | /private/var/folders/*)
                reason_init "scratch app is under a temp dir: $scratch_real"
                ;;
        esac
    fi
    if [ ! -f "$STREAM_PID_FILE" ]; then
        reason_init "signpost stream pid file missing"
    else
        stream_pid="$(cat "$STREAM_PID_FILE")"
        if ! kill -0 "$stream_pid" 2>/dev/null; then
            reason_init "signpost stream pid $stream_pid is dead"
        fi
    fi
    [ -s "$SIGNPOST_LOG" ] || reason_init "signpost log $SIGNPOST_LOG is missing or empty"
    if [ "$ok" = "true" ]; then
        printf '{"ok":true,"production_pid":%s,"scratch_pid":%s,"scratch_claim_pid":%s,"production_claim_pid":%s}\n' \
            "$rec_prod" "${scratch_pid:-0}" "${scratch_claim:-0}" "${prod_claim:-0}"
        return 0
    fi
    printf '{"ok":false,"reason":%s,"production_pid":%s,"scratch_pid":%s,"scratch_count":%s}\n' \
        "$(jstr "$reason")" "${rec_prod:-0}" "${scratch_pid:-0}" "${scratch_count:-0}"
    return 1
}

do_wake() {
    # wake SLUG TITLE [--channel auto|desktop|off]: add jobs:SLUG to the
    # disposable vault, wake it now, print wake_id, notification_channel,
    # and notified.
    local slug="" title="" channel="auto" wake_out wake_id notified receipt_channel
    mac_only
    need python3
    command -v bob >/dev/null 2>&1 || die "missing required command: bob"
    if [ "$#" -lt 2 ]; then
        die "usage: snooze-accept.sh wake SLUG TITLE [--channel auto|desktop|off]"
    fi
    slug="$1"
    title="$2"
    shift 2
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --channel)
                channel="${2:?missing --channel value}"
                shift 2
                ;;
            *)
                die "wake: unexpected argument $1"
                ;;
        esac
    done
    case "$slug" in
        '' | *[!A-Za-z0-9_-]*)
            die "slug must match [A-Za-z0-9_-]+ (got $slug)"
            ;;
    esac
    [ -d "$VAULT_DIR" ] || die "no harness vault; run up first"
    ensure_vault
    write_channel_config "$channel"
    if ! grep -q "\\^$slug" "$VAULT_DIR/jobs.md" 2>/dev/null; then
        printf -- '- [ ] #task %s ^%s\n' "$title" "$slug" >>"$VAULT_DIR/jobs.md"
    fi
    scratch_env
    bob snooze add "jobs:$slug" +5m -f json >/dev/null 2>"$EVIDENCE_DIR/add-$slug.err" \
        || die "bob snooze add failed: $(cat "$EVIDENCE_DIR/add-$slug.err")"
    wake_out="$(bob snooze wake "jobs:$slug" -f json 2>"$EVIDENCE_DIR/wake-$slug.err")" \
        || die "bob snooze wake failed: $(cat "$EVIDENCE_DIR/wake-$slug.err")"
    printf '%s' "$wake_out" >"$EVIDENCE_DIR/wake-$slug.json"
    wake_id="$(printf '%s' "$wake_out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("wake_id") or "")')" \
        || die "wake output is not JSON"
    notified="$(printf '%s' "$wake_out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("notified") or "")')" \
        || die "wake output is not JSON"
    receipt_channel="$(python3 -c 'import json; print(json.load(open("'"$STATE_DIR"'/bob-cli/snooze/last-wake.json")).get("notification_channel", ""))' 2>/dev/null)" \
        || receipt_channel=""
    [ -n "$wake_id" ] || die "wake produced no wake_id"
    printf '{"status":"wake","slug":%s,"channel":%s,"wake_id":%s,"notification_channel":%s,"notified":%s}\n' \
        "$(jstr "$slug")" "$(jstr "$channel")" "$(jstr "$wake_id")" \
        "$(jstr "$receipt_channel")" "$(jstr "$notified")"
}

do_ping() {
    mac_only
    need notifyutil
    notifyutil -p "$WOKEN_KEY" || die "notifyutil -p failed"
    printf '{"status":"ping","key":%s}\n' "$(jstr "$WOKEN_KEY")"
}

do_stop() {
    # Stop the scratch app and the signpost stream by recorded PID only.
    mac_only
    load_variant
    local scratch_pid="" stream_pid=""
    if [ -f "$SCRATCH_PID_FILE" ]; then
        scratch_pid="$(cat "$SCRATCH_PID_FILE")"
    fi
    if [ -f "$STREAM_PID_FILE" ]; then
        stream_pid="$(cat "$STREAM_PID_FILE")"
    fi
    stop_stream
    if [ -f "$SCRATCH_PID_FILE" ]; then
        stop_pid "$SCRATCH_PID_FILE" 10
        rm -f "$SCRATCH_PID_FILE"
    fi
    printf '{"status":"stopped","scratch_pid":%s,"stream_pid":%s}\n' \
        "$(jstr "${scratch_pid:-none}")" "$(jstr "${stream_pid:-none}")"
}

do_restart() {
    # Stop, then relaunch the way up did, with a fresh signpost stream.
    mac_only
    local old_pid="" scratch_pid
    if [ -f "$SCRATCH_PID_FILE" ]; then
        old_pid="$(cat "$SCRATCH_PID_FILE")"
    fi
    do_stop >/dev/null
    scratch_pid="$(launch_scratch)"
    stop_stream
    start_stream "$scratch_pid"
    do_guard >/dev/null || die "guard failed after restart; see guard output"
    printf '{"status":"restarted","old_pid":%s,"scratch_pid":%s}\n' \
        "$(jstr "${old_pid:-none}")" "$scratch_pid"
}

do_status() {
    mac_only
    load_variant
    HARNESS_ROOT="$ROOT" SCRATCH_APP="$SCRATCH_APP" ACCEPT_ID="$ACCEPT_ID" python3 <<'EOF'
import json, os

root = os.environ["HARNESS_ROOT"]
out = {"status": "status"}


def notification_client():
    try:
        with open(os.path.join(root, "evidence/usernoted-client.log")) as fh:
            body = fh.read()
    except OSError:
        return "unknown"
    accept_id = os.environ.get("ACCEPT_ID", "")
    if accept_id and ("Connection %s with path:" % accept_id) in body:
        return "accepted"
    return "unknown"


def read(path):
    try:
        with open(os.path.join(root, path)) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def load_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


out["production_pid"] = read("production.pid")
out["scratch_pid"] = read("scratch.pid")
out["harness_sha"] = read("harness-sha")
out["scratch_app"] = os.environ.get("SCRATCH_APP", "")
out["notification_client"] = notification_client()
state = os.path.join(root, "state")
out["claim"] = load_json(
    os.path.join(state, "bob-cli/snooze/notifier.json"))
receipt = load_json(os.path.join(state, "bob-cli/snooze/last-wake.json"))
if isinstance(receipt, dict):
    out["receipt"] = {
        "wake_id": receipt.get("wake_id"),
        "notification_channel": receipt.get("notification_channel"),
        "woken_at": receipt.get("woken_at"),
        "tasks": receipt.get("tasks"),
    }
else:
    out["receipt"] = None
out["scratch_alive"] = alive(out["scratch_pid"]) if out["scratch_pid"] else False
lines = []
try:
    with open(os.path.join(root, "evidence/signposts.log")) as fh:
        for line in fh:
            if "snooze-" in line:
                lines.append(line.rstrip("\n"))
except OSError:
    pass
out["recent_snooze_signposts"] = lines[-15:]
print(json.dumps(out))
EOF
}

do_down() {
    mac_only
    load_variant
    local leftovers="" nc_hint="System Settings > Notifications > Bob Mac Capture Accept"
    local legacy_app="$ROOT/$ACCEPT_NAME.app"
    # Stop by recorded PIDs only; never by name or bundle ID.
    stop_stream
    if [ -f "$SCRATCH_PID_FILE" ]; then
        stop_pid "$SCRATCH_PID_FILE" 10
    fi
    if [ -n "$(find_scratch_pids)" ]; then
        leftovers="scratch processes still match after stop: $(find_scratch_pids | tr '\n' ' ')"
    fi
    defaults delete "$ACCEPT_ID" 2>/dev/null || true
    defaults delete "$NOAUTH_ID" 2>/dev/null || true
    for name in "Bob Mac Capture Accept" "Bob Mac Capture Accept Noauth"; do
        app="$SCRATCH_APP_DIR/$name.app"
        if [ -d "$app" ]; then
            "$LSREGISTER" -u "$app" 2>/dev/null || true
        fi
    done
    if [ -d "$legacy_app" ]; then
        "$LSREGISTER" -u "$legacy_app" 2>/dev/null || true
    fi
    if [ -e "$ROOT" ]; then
        rm -rf "$ROOT"
    fi
    rm -rf "$SCRATCH_APP_DIR"
    if [ -e "$SCRATCH_APP_DIR" ]; then
        if [ -n "$leftovers" ]; then
            leftovers="$leftovers; app dir still exists: $SCRATCH_APP_DIR"
        else
            leftovers="app dir still exists: $SCRATCH_APP_DIR"
        fi
    fi
    printf '{"status":"down","removed":true,"leftover":%s,"notification_center":%s}\n' \
        "$(jstr "${leftovers:-none}")" \
        "$(jstr "$nc_hint")"
}

install_scratch_bundle() {
    local src_repo="$1" sha="$2" src_bundle plist_id
    [ -d "$src_repo/.git" ] || die "no git checkout at $src_repo"
    src_sha="$(git -C "$src_repo" rev-parse HEAD)"
    [ "$src_sha" = "$sha" ] || die "source checkout is $src_sha, not requested $sha"
    mkdir -p "$SRC_DIR"
    rsync -a --delete --exclude .build --exclude .git "$src_repo/" "$SRC_DIR/"
    (cd "$SRC_DIR" && ./Scripts/bundle.sh --identity - >/dev/null) \
        || die "bundle.sh failed"
    src_bundle="$SRC_DIR/.build/bundle/Bob Mac Capture.app"
    [ -d "$src_bundle" ] || die "bundle missing at $src_bundle"
    rm -rf "$SCRATCH_APP"
    mkdir -p "$SCRATCH_APP_DIR"
    cp -R "$src_bundle" "$SCRATCH_APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $ACCEPT_ID" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy bundle id failed"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $ACCEPT_NAME" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy bundle name failed"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $ACCEPT_NAME" \
        "$SCRATCH_APP/Contents/Info.plist" || die "PlistBuddy display name failed"
    plist_id="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "$SCRATCH_APP/Contents/Info.plist")" || die "PlistBuddy print failed"
    [ "$plist_id" = "$ACCEPT_ID" ] || die "bundle id is $plist_id, not $ACCEPT_ID"
    /usr/bin/codesign --force --deep --sign - "$SCRATCH_APP" \
        || die "ad-hoc sign failed"
    /usr/bin/codesign --verify --deep --strict "$SCRATCH_APP" \
        || die "codesign verify failed"
}

seed_accept_defaults() {
    defaults write "$ACCEPT_ID" bobDirectory -string "$VAULT_DIR"
    defaults write "$ACCEPT_ID" useProductionHotkey -bool false
    defaults write "$ACCEPT_ID" captureAliasHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" refsHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" refsAliasHotkeyEnabled -bool false
    defaults write "$ACCEPT_ID" snoozeAcceptanceProbe -bool true
}

do_rebuild() {
    local sha="" src_repo scratch_pid
    mac_only
    load_variant
    need git
    need rsync
    [ -x /usr/libexec/PlistBuddy ] || die "missing required command: PlistBuddy"
    [ -d "$ROOT" ] || die "no harness root; run up first"
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --sha)
                sha="${2:?missing --sha value}"
                shift 2
                ;;
            *)
                die "rebuild: unexpected argument $1"
                ;;
        esac
    done
    src_repo="$(script_repo_root)"
    if [ -z "$sha" ]; then
        sha="$(git -C "$src_repo" rev-parse HEAD)"
    fi
    do_stop >/dev/null
    install_scratch_bundle "$src_repo" "$sha"
    printf '%s' "$sha" >"$HARNESS_SHA_FILE"
    scratch_pid="$(launch_scratch)"
    stop_stream
    start_stream "$scratch_pid"
    do_guard >/dev/null || die "guard failed after rebuild; see guard output"
    printf '{"status":"rebuilt","sha":%s,"scratch_pid":%s,"bundle_id":%s}\n' \
        "$(jstr "$sha")" "$scratch_pid" "$(jstr "$ACCEPT_ID")"
}

do_probe() {
    local seq_file seq request tmp waited response
    mac_only
    load_variant
    need python3
    need notifyutil
    [ -d "$ROOT" ] || die "no harness root; run up first"
    if [ "$#" -lt 1 ]; then
        die "usage: snooze-accept.sh probe COMMAND [ARGS...]"
    fi
    mkdir -p "$(probe_dir)"
    seq_file="$(probe_dir)/seq"
    if [ -f "$seq_file" ]; then
        seq=$(($(cat "$seq_file") + 1))
    else
        seq=1
    fi
    printf '%s' "$seq" >"$seq_file"
    request="$(python3 -c 'import json,sys
print(json.dumps({"seq": int(sys.argv[1]), "command": sys.argv[2], "args": sys.argv[3:]}))
' "$seq" "$@")"
    tmp="$(mktemp "$(probe_dir)/request.XXXXXX")"
    printf '%s' "$request" >"$tmp"
    mv "$tmp" "$(probe_dir)/request.json"
    notifyutil -p "$PROBE_KEY" || die "notifyutil -p $PROBE_KEY failed"
    waited=0
    response="$(probe_dir)/response-$seq.json"
    while [ "$waited" -lt 50 ]; do
        if [ -f "$response" ]; then
            cat "$response"
            printf '\n'
            return 0
        fi
        sleep 0.1
        waited=$((waited + 1))
    done
    die "probe response $response did not appear"
}

do_idle() {
    mac_only
    python3 <<'PY'
import json, os, re, subprocess, ctypes
from ctypes import c_uint32, c_int, c_double

out = {
    "status": "idle",
    "hid_idle_seconds": None,
    "screen_locked": False,
    "displays_asleep": False,
    "prevent_display_sleep": False,
    "no_display_sleep": False,
}

try:
    hid = subprocess.check_output(
        ["ioreg", "-c", "IOHIDSystem"], text=True, stderr=subprocess.DEVNULL
    )
    match = re.search(r'"HIDIdleTime"\s*=\s*(\d+)', hid)
    if match:
        out["hid_idle_seconds"] = int(match.group(1)) / 1_000_000_000
except (OSError, subprocess.CalledProcessError):
    pass

try:
    root = subprocess.check_output(
        ["ioreg", "-n", "Root", "-d1"], text=True, stderr=subprocess.DEVNULL
    )
    if re.search(r'"CGSSessionScreenIsLocked"\s*=\s*Yes', root):
        out["screen_locked"] = True
    elif re.search(r"CGSSessionScreenIsLocked.*Yes", root):
        out["screen_locked"] = True
except (OSError, subprocess.CalledProcessError):
    pass

try:
    cg = ctypes.cdll.LoadLibrary(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    )
    cg.CGMainDisplayID.restype = c_uint32
    cg.CGDisplayIsAsleep.argtypes = [c_uint32]
    cg.CGDisplayIsAsleep.restype = c_int
    out["displays_asleep"] = bool(cg.CGDisplayIsAsleep(cg.CGMainDisplayID()))
except OSError:
    pass

try:
    assertions = subprocess.check_output(
        ["pmset", "-g", "assertions"], text=True, stderr=subprocess.DEVNULL
    )
    if "PreventUserIdleDisplaySleep" in assertions and re.search(
        r"PreventUserIdleDisplaySleep\s+[1-9]", assertions
    ):
        out["prevent_display_sleep"] = True
    if re.search(r"\bNoDisplaySleep\b", assertions):
        out["no_display_sleep"] = True
except (OSError, subprocess.CalledProcessError):
    pass

print(json.dumps(out))
PY
}

do_evidence() {
    local since="" pid dest
    mac_only
    load_variant
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --since)
                since="${2:?missing --since value}"
                shift 2
                ;;
            *)
                die "evidence: unexpected argument $1"
                ;;
        esac
    done
    [ -n "$since" ] || die "usage: snooze-accept.sh evidence --since T"
    [ -f "$SCRATCH_PID_FILE" ] || die "no scratch pid; run up first"
    pid="$(cat "$SCRATCH_PID_FILE")"
    mkdir -p "$EVIDENCE_DIR"
    dest="$EVIDENCE_DIR/signposts-since.log"
    case "$since" in
        *[smhd])
            /usr/bin/log show --signpost --last "$since" --style compact \
                --predicate "subsystem == \"$SUBSYSTEM\" AND processIdentifier == $pid" \
                >"$dest" 2>"$EVIDENCE_DIR/signposts-since.err" || true
            ;;
        *)
            /usr/bin/log show --signpost --start "$since" --style compact \
                --predicate "subsystem == \"$SUBSYSTEM\" AND processIdentifier == $pid" \
                >"$dest" 2>"$EVIDENCE_DIR/signposts-since.err" || true
            ;;
    esac
    printf '{"status":"evidence","pid":%s,"since":%s,"path":%s,"bytes":%s}\n' \
        "$pid" "$(jstr "$since")" "$(jstr "$dest")" "$(wc -c <"$dest" | tr -d ' ')"
}

write_shim() {
    local mode="$1" real_bob shim log
    real_bob="$(command -v bob)" || die "missing required command: bob"
    mkdir -p "$STATE_DIR/shim" "$EVIDENCE_DIR"
    shim="$STATE_DIR/shim/bob"
    log="$EVIDENCE_DIR/shim-argv.log"
    touch "$log"
    python3 - "$mode" "$real_bob" "$shim" "$log" <<'PY'
import os, sys
mode, real_bob, shim, log = sys.argv[1:]
if mode == "passthrough":
    body = """#!/bin/bash
printf 'argv=%%s\\n' "$*" >>%s
exec %s "$@"
""" % (repr(log), repr(real_bob))
elif mode == "oldbob":
    body = """#!/bin/bash
printf 'argv=%%s\\n' "$*" >>%s
if [ "${1:-}" = "snooze" ] && { [ "${2:-}" = "-f" ] || [ "${2:-}" = "--format" ] || [ -z "${2:-}" ]; }; then
  output="$(%s "$@" )"
  status=$?
  printf '%%s' "$output" | python3 -c 'import json,sys
raw=sys.stdin.read()
try:
    payload=json.loads(raw)
except Exception:
    sys.stdout.write(raw)
    raise SystemExit(0)
payload.pop("wake_notice_version", None)
json.dump(payload, sys.stdout)
print()
'
  exit $status
fi
exec %s "$@"
""" % (repr(log), repr(real_bob), repr(real_bob))
else:
    raise SystemExit("unknown shim mode")
os.makedirs(os.path.dirname(shim), exist_ok=True)
with open(shim, "w") as fh:
    fh.write(body)
os.chmod(shim, 0o755)
print(shim)
PY
}

do_shim() {
    local mode="${1:-}"
    mac_only
    load_variant
    [ -d "$ROOT" ] || die "no harness root; run up first"
    case "$mode" in
        passthrough | oldbob)
            shim_path="$(write_shim "$mode")"
            do_probe set bobExecutableOverride "$shim_path" >/dev/null
            printf '{"status":"shim","mode":%s,"path":%s}\n' \
                "$(jstr "$mode")" "$(jstr "$shim_path")"
            ;;
        off)
            do_probe set bobExecutableOverride "" >/dev/null
            printf '{"status":"shim","mode":"off"}\n'
            ;;
        *)
            die "usage: snooze-accept.sh shim passthrough|oldbob|off"
            ;;
    esac
}

do_variant() {
    local which="${1:-}" src_repo sha scratch_pid
    mac_only
    [ -d "$ROOT" ] || die "no harness root; run up first"
    case "$which" in
        noauth | accept) ;;
        *) die "usage: snooze-accept.sh variant noauth|accept" ;;
    esac
    do_stop >/dev/null
    printf '%s\n' "$which" >"$ROOT/variant"
    load_variant
    src_repo="$(script_repo_root)"
    sha="$(cat "$HARNESS_SHA_FILE" 2>/dev/null || git -C "$src_repo" rev-parse HEAD)"
    install_scratch_bundle "$src_repo" "$sha"
    seed_accept_defaults
    scratch_pid="$(launch_scratch)"
    stop_stream
    start_stream "$scratch_pid"
    do_guard >/dev/null || die "guard failed after variant $which"
    printf '{"status":"variant","variant":%s,"bundle_id":%s,"scratch_pid":%s}\n' \
        "$(jstr "$which")" "$(jstr "$ACCEPT_ID")" "$scratch_pid"
}

idle_field() {
    python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"
}

do_lockwatch() {
    local lock_wait=0 idle_json locked hid prevent asleep last_sleep=0
    local wake_n=0 wake_id="" pass=0 unlock_wait=0
    mac_only
    load_variant
    [ -d "$ROOT" ] || die "no harness root; run up first"
    mkdir -p "$EVIDENCE_DIR"
    printf '{"status":"lockwatch","phase":"waiting-lock"}\n'
    while true; do
        idle_json="$(do_idle)"
        locked="$(printf '%s' "$idle_json" | idle_field screen_locked)"
        hid="$(printf '%s' "$idle_json" | idle_field hid_idle_seconds)"
        prevent="$(printf '%s' "$idle_json" | idle_field prevent_display_sleep)"
        asleep="$(printf '%s' "$idle_json" | idle_field displays_asleep)"
        if [ "$locked" = "True" ] || [ "$locked" = "true" ]; then
            lock_wait=$((lock_wait + 1))
        else
            # Accelerator: HID idle >= 30 min, unlocked, display awake,
            # no display-sleep assertion, at most once per 6 h.
            case "$hid" in
                None | none | "") hid_int=0 ;;
                *) hid_int="${hid%.*}" ;;
            esac
            hid_int="${hid_int:-0}"
            now_epoch="$(date +%s)"
            if [ "$hid_int" -ge 1800 ] && [ "$asleep" != "True" ] && [ "$asleep" != "true" ] \
                && [ "$prevent" != "True" ] && [ "$prevent" != "true" ]; then
                if [ $((now_epoch - last_sleep)) -ge 21600 ]; then
                    pmset displaysleepnow >/dev/null 2>&1 || true
                    last_sleep="$now_epoch"
                    printf '{"status":"lockwatch","phase":"accelerator","hid_idle_seconds":%s}\n' \
                        "$(jstr "$hid")"
                fi
            fi
            lock_wait=0
        fi
        if [ "$lock_wait" -ge 10 ]; then
            do_guard >/dev/null || die "guard failed inside lockwatch"
            wake_n=$((wake_n + 1))
            wake_out="$(do_wake "lock$wake_n" "Lock check $wake_n (test, no action needed)" --channel auto)"
            wake_id="$(printf '%s' "$wake_out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("wake_id") or "")')"
            printf '{"status":"lockwatch","phase":"held","wake_id":%s,"lock_seconds":%s}\n' \
                "$(jstr "$wake_id")" "$lock_wait"
            while true; do
                idle_json="$(do_idle)"
                locked="$(printf '%s' "$idle_json" | idle_field screen_locked)"
                snap="$(do_probe snapshot 2>/dev/null || true)"
                printf '{"status":"lockwatch","phase":"held-snapshot","wake_id":%s,"idle":%s,"snapshot":%s}\n' \
                    "$(jstr "$wake_id")" "$idle_json" "${snap:-null}"
                if [ "$locked" != "True" ] && [ "$locked" != "true" ]; then
                    if [ "$lock_wait" -lt 10 ]; then
                        printf '{"status":"lockwatch","phase":"retry","reason":"unlock within 10s of lock"}\n'
                        break
                    fi
                    unlock_wait=0
                    printf '{"status":"lockwatch","phase":"unlocking","wake_id":%s}\n' \
                        "$(jstr "$wake_id")"
                    while [ "$unlock_wait" -lt 60 ]; do
                        sleep 0.5
                        unlock_wait=$((unlock_wait + 1))
                        snap="$(do_probe snapshot 2>/dev/null || true)"
                        python3 - "$wake_id" "$snap" <<'PY' && pass=1
import json, sys
wake = sys.argv[1]
try:
    snap = json.loads(sys.argv[2] or "{}")
except Exception:
    raise SystemExit(1)
result = snap.get("result") or snap
hud = (result.get("hud") or {}) if isinstance(result, dict) else {}
coord = (result.get("coordinator") or {}) if isinstance(result, dict) else {}
events = (result.get("last_events") or {}) if isinstance(result, dict) else {}
records = (result.get("records") or {}) if isinstance(result, dict) else {}
visible = hud.get("visible") is True
presenting = coord.get("state") == "presenting"
announced = bool(events.get("announcement_text"))
chimed = events.get("chime_played") is True
delivered = records.get("delivered") or []
if visible and presenting and announced and chimed and delivered:
    raise SystemExit(0)
raise SystemExit(1)
PY
                        if [ "$pass" = "1" ] && [ "$unlock_wait" -ge 3 ]; then
                            printf '{"status":"lockwatch","phase":"pass","wake_id":%s,"unlock_seconds":%s}\n' \
                                "$(jstr "$wake_id")" "$(python3 -c "print($unlock_wait * 0.5)")"
                            return 0
                        fi
                    done
                    printf '{"status":"lockwatch","phase":"unlock-timeout","wake_id":%s}\n' \
                        "$(jstr "$wake_id")"
                    break
                fi
                sleep 60
                lock_wait=$((lock_wait + 60))
            done
            lock_wait=0
        fi
        sleep 1
    done
}

main() {
    if [ "$#" -lt 1 ]; then
        usage >&2
        exit 2
    fi
    local cmd="$1"
    shift
    case "$cmd" in
        up) do_up "$@" ;;
        rebuild) do_rebuild "$@" ;;
        guard) do_guard "$@" ;;
        wake) do_wake "$@" ;;
        ping) do_ping "$@" ;;
        probe) do_probe "$@" ;;
        idle) do_idle "$@" ;;
        evidence) do_evidence "$@" ;;
        shim) do_shim "$@" ;;
        variant) do_variant "$@" ;;
        lockwatch) do_lockwatch "$@" ;;
        stop) do_stop "$@" ;;
        restart) do_restart "$@" ;;
        status) do_status "$@" ;;
        down) do_down "$@" ;;
        -h | --help | help) usage ;;
        *) die "unknown subcommand $cmd" ;;
    esac
}

main "$@"

