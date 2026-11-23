#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

export BILI_INSTALL_DIR="$TEST_ROOT/install"
export BILI_SCRIPT_DST="$TEST_ROOT/bin/bili"
export BILI_SERVICE_FILE="$TEST_ROOT/bililive-go.service"
export BILI_SCRIPT_LIBRARY_ONLY=1

# shellcheck source=../bili.sh
source "$SCRIPT_DIR/bili.sh"
eval "$(declare -f prepare_binary | sed '1s/prepare_binary/real_prepare_binary/')"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"
}

assert_contains() {
    [[ "$1" == *"$2"* ]] || fail "$3 (missing '$2')"
}

reset_case() {
    rm -rf "$BILI_INSTALL_DIR"
    mkdir -p "$BILI_INSTALL_DIR"
    printf 'old-binary\n' > "$BIN_PATH"
    printf 'vOld\n' > "$VER_FILE"
    printf 'running\n' > "$TEST_ROOT/state"
    : > "$TEST_ROOT/events"
    printf '0\n' > "$TEST_ROOT/start-count"
    PREPARED_DIR=""
    PREPARED_BINARY=""
    PREP_FAIL=0
    STOP_FAIL=0
    START_FAIL_FIRST=0
    FAIL_VERSION_PUBLISH=0
}

get_latest_version() { printf 'vNew\n'; }
need_root() { :; }
svc_running() { [[ "$(<"$TEST_ROOT/state")" == running ]]; }
svc_stop() {
    printf 'stop\n' >> "$TEST_ROOT/events"
    (( STOP_FAIL == 0 )) || return 1
    printf 'stopped\n' > "$TEST_ROOT/state"
}
svc_start() {
    local count
    printf 'start\n' >> "$TEST_ROOT/events"
    count=$(<"$TEST_ROOT/start-count")
    count=$((count + 1))
    printf '%s\n' "$count" > "$TEST_ROOT/start-count"
    if (( START_FAIL_FIRST && count == 1 )); then
        return 1
    fi
    printf 'running\n' > "$TEST_ROOT/state"
}
wait_for_service_running() { svc_running; }
prepare_binary() {
    printf 'prepare\n' >> "$TEST_ROOT/events"
    (( PREP_FAIL == 0 )) || return 1
    PREPARED_DIR=$(mktemp -d "$TEST_ROOT/prepared.XXXXXX") || return 1
    PREPARED_BINARY="$PREPARED_DIR/bililive-go"
    printf 'new-binary\n' > "$PREPARED_BINARY"
}
cleanup_prepared_binary() {
    [[ -z "$PREPARED_DIR" ]] || rm -rf "$PREPARED_DIR"
    PREPARED_DIR=""
    PREPARED_BINARY=""
}

cmd_update_yes() {
    ( cmd_update <<< 'y' )
}

reset_case
PREP_FAIL=1
if cmd_update_yes > "$TEST_ROOT/output" 2>&1; then
    fail 'download/preparation failure should fail update'
fi
assert_eq "$(<"$TEST_ROOT/state")" running 'preparation failure must leave service running'
assert_eq "$(<"$BIN_PATH")" 'old-binary' 'preparation failure must keep old binary'
assert_eq "$(<"$VER_FILE")" 'vOld' 'preparation failure must keep old version'
assert_eq "$(<"$TEST_ROOT/events")" 'prepare' 'preparation failure must happen before service stop'
printf 'PASS: preparation failure leaves the live version untouched\n'

reset_case
cmd_update_yes > "$TEST_ROOT/output" 2>&1 || fail 'running-service update should succeed'
assert_eq "$(<"$BIN_PATH")" 'new-binary' 'successful update should publish new binary'
assert_eq "$(<"$VER_FILE")" 'vNew' 'successful update should publish new version'
assert_eq "$(<"$TEST_ROOT/state")" running 'successful update should restore running state'
assert_contains "$(<"$TEST_ROOT/events")" $'prepare\nstop\nstart' 'prepare, stop and start order'
assert_eq "$(find "$BILI_INSTALL_DIR" -maxdepth 1 -name '.update.*' -print -quit)" '' 'success should remove backup directory'
printf 'PASS: successful update stages before stopping and resumes service\n'

reset_case
printf 'stopped\n' > "$TEST_ROOT/state"
cmd_update_yes > "$TEST_ROOT/output" 2>&1 || fail 'stopped-service update should succeed'
assert_eq "$(<"$BIN_PATH")" 'new-binary' 'stopped service should still receive new binary'
assert_eq "$(<"$TEST_ROOT/state")" stopped 'update must preserve pre-existing stopped state'
assert_eq "$(<"$TEST_ROOT/events")" 'prepare' 'stopped service must not be stopped or started'
printf 'PASS: update preserves a pre-existing stopped state\n'

reset_case
START_FAIL_FIRST=1
if cmd_update_yes > "$TEST_ROOT/output" 2>&1; then
    fail 'failed new-version startup should fail update'
fi
assert_eq "$(<"$BIN_PATH")" 'old-binary' 'startup failure should restore old binary'
assert_eq "$(<"$VER_FILE")" 'vOld' 'startup failure should restore old version'
assert_eq "$(<"$TEST_ROOT/state")" running 'startup failure should restart old service'
assert_eq "$(<"$TEST_ROOT/start-count")" 2 'rollback should attempt to start the old service'
assert_eq "$(find "$BILI_INSTALL_DIR" -maxdepth 1 -name '.update.*' -print -quit)" '' 'successful rollback should remove backup directory'
printf 'PASS: failed startup restores binary, version and running state\n'

reset_case
FAIL_VERSION_PUBLISH=1
mv() {
    if (( FAIL_VERSION_PUBLISH )) && [[ "${2:-}" == "$VER_FILE.new."* ]]; then
        FAIL_VERSION_PUBLISH=0
        return 1
    fi
    command mv "$@"
}
if cmd_update_yes > "$TEST_ROOT/output" 2>&1; then
    fail 'failed version publication should fail update'
fi
unset -f mv
assert_eq "$(<"$BIN_PATH")" 'old-binary' 'publication failure should restore old binary'
assert_eq "$(<"$VER_FILE")" 'vOld' 'publication failure should restore old version'
assert_eq "$(<"$TEST_ROOT/state")" running 'publication failure should restore running state'
printf 'PASS: partial publication failure rolls the update back\n'

reset_case
STOP_FAIL=1
if cmd_update_yes > "$TEST_ROOT/output" 2>&1; then
    fail 'failed service stop should fail update'
fi
assert_eq "$(<"$BIN_PATH")" 'old-binary' 'stop failure must not publish new binary'
assert_eq "$(<"$VER_FILE")" 'vOld' 'stop failure must keep old version'
assert_eq "$(<"$TEST_ROOT/state")" running 'stop failure must preserve running service'
printf 'PASS: failed service stop prevents publication\n'

test_prepare_binary() {
    local fixture="$TEST_ROOT/package"
    local mockbin="$TEST_ROOT/mockbin"
    local digest
    mkdir -p "$fixture" "$mockbin"
    printf 'fixture-binary\n' > "$fixture/bililive-go"
    tar -czf "$TEST_ROOT/package.tar.gz" -C "$fixture" bililive-go
    digest=$(sha256sum "$TEST_ROOT/package.tar.gz")
    digest=${digest%% *}
    cat > "$mockbin/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
out=''
while (($#)); do
    if [[ "$1" == -o ]]; then
        out="$2"
        shift 2
    else
        shift
    fi
done
[[ -n "$out" ]] || exit 2
cp "$BILI_TEST_ARCHIVE" "$out"
MOCK_CURL
    chmod +x "$mockbin/curl"
    export BILI_TEST_ARCHIVE="$TEST_ROOT/package.tar.gz"
    BILI_TEST_DIGEST="$digest"
    PATH="$mockbin:$PATH"
    get_arch() { printf 'amd64\n'; }
    release_asset_for_tag() {
        printf 'https://github.com/bililive-go/bililive-go/releases/download/vNew/bililive-linux-amd64.tar.gz\tsha256:%s\n' "$BILI_TEST_DIGEST"
    }

    PREP_FAIL=0
    real_prepare_binary vNew > "$TEST_ROOT/output" 2>&1 || { printf '%s\n' "$(<"$TEST_ROOT/output")" >&2; fail 'valid package should prepare successfully'; }
    assert_eq "$(<"$PREPARED_BINARY")" 'fixture-binary' 'prepared binary content'
    cleanup_prepared_binary

    release_asset_for_tag() {
        printf 'https://github.com/bililive-go/bililive-go/releases/download/vNew/bililive-linux-amd64.tar.gz\tsha256:%064d\n' 0
    }
    if real_prepare_binary vNew > "$TEST_ROOT/output" 2>&1; then
        fail 'invalid package checksum should be rejected'
    fi
    assert_eq "$PREPARED_DIR" '' 'checksum failure should clean its temporary directory'

    release_asset_for_tag() {
        printf 'https://github.com/bililive-go/bililive-go/releases/download/vNew/bililive-linux-amd64.tar.gz\tsha256:%s\n' "$BILI_TEST_DIGEST"
    }
    printf 'not a gzip archive\n' > "$BILI_TEST_ARCHIVE"
    if real_prepare_binary vNew > "$TEST_ROOT/output" 2>&1; then
        fail 'invalid archive should be rejected'
    fi
    assert_eq "$PREPARED_DIR" '' 'archive failure should clean its temporary directory'

    printf 'empty-package\n' > "$TEST_ROOT/empty-file"
    tar -czf "$BILI_TEST_ARCHIVE" -C "$TEST_ROOT" empty-file
    digest=$(sha256sum "$BILI_TEST_ARCHIVE")
    BILI_TEST_DIGEST=${digest%% *}
    release_asset_for_tag() {
        printf 'https://github.com/bililive-go/bililive-go/releases/download/vNew/bililive-linux-amd64.tar.gz\tsha256:%s\n' "$BILI_TEST_DIGEST"
    }
    if real_prepare_binary vNew > "$TEST_ROOT/output" 2>&1; then
        fail 'archive without the executable should be rejected'
    fi
    assert_eq "$PREPARED_DIR" '' 'missing executable should clean its temporary directory'
    unset -f get_arch release_asset_for_tag
    PATH=${PATH#"$mockbin:"}
    printf 'PASS: package preparation extracts, verifies SHA256 and rejects bad archives\n'
}

test_prepare_binary
printf '\nAll update regression tests passed.\n'
