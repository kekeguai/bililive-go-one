#!/usr/bin/env bash

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export BILI_INSTALL_DIR="$TEST_ROOT/install"
export BILI_SCRIPT_DST="$TEST_ROOT/bin/bili"
export BILI_SERVICE_FILE="$TEST_ROOT/service"
export BILI_SCRIPT_LIBRARY_ONLY=1
source "$SCRIPT_DIR/bili.sh"
eval "$(declare -f run_menu_action | sed '1s/run_menu_action/real_run_menu_action/')"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"
}

reset_calls() {
    CALLS=()
    PORT_ARG=unset
}

cmd_install() { CALLS+=(install); }
cmd_restart() { CALLS+=(restart); }
cmd_start() { CALLS+=(start); }
cmd_stop() { CALLS+=(stop); }
cmd_status() { CALLS+=(status); }
cmd_port() { CALLS+=(port); PORT_ARG="$1"; }
cmd_update() { CALLS+=(update); }
cmd_log() { CALLS+=(log); }
cmd_uninstall() { CALLS+=(uninstall); }

for option in {1..9}; do
    reset_calls
    real_run_menu_action "$option" || fail "menu option $option should be handled"
    case "$option" in
        1) expected=install ;;
        2) expected=restart ;;
        3) expected=start ;;
        4) expected=stop ;;
        5) expected=status ;;
        6) expected=port ;;
        7) expected=update ;;
        8) expected=log ;;
        9) expected=uninstall ;;
    esac
    assert_eq "${CALLS[*]}" "$expected" "menu option $option dispatch"
    if [[ "$option" == 6 ]]; then
        assert_eq "$PORT_ARG" '' 'menu port option should prompt for the new port'
    fi
done
printf 'PASS: numeric options dispatch to existing commands\n'

reset_calls
real_run_menu_action 0 && fail 'exit option should terminate menu' || status=$?
assert_eq "$status" 2 'exit option status'
assert_eq "${CALLS[*]}" '' 'exit option should not dispatch a command'

reset_calls
real_run_menu_action 99 > "$TEST_ROOT/invalid" 2>&1 || fail 'invalid option should return to menu'
assert_eq "${CALLS[*]}" '' 'invalid option should not dispatch a command'
grep -q '无效选项' "$TEST_ROOT/invalid" || fail 'invalid option should show a warning'
printf 'PASS: exit and invalid options are handled safely\n'

menu_is_interactive() { return 1; }
if main_menu > "$TEST_ROOT/noninteractive" 2>&1; then
    fail 'menu should reject a non-interactive terminal'
fi
grep -q '需要交互式终端' "$TEST_ROOT/noninteractive" || fail 'noninteractive call should explain the requirement'
printf 'PASS: non-interactive menu exits without waiting for input\n'

menu_is_interactive() { return 0; }
menu_count=0
show_menu() { menu_count=$((menu_count + 1)); }
menu_responses=(1 '' 0)
menu_response_index=0
read() {
    local variable="$3"
    (( menu_response_index < ${#menu_responses[@]} )) || return 1
    printf -v "$variable" '%s' "${menu_responses[menu_response_index]}"
    menu_response_index=$((menu_response_index + 1))
}
reset_calls
main_menu || fail 'interactive menu should exit cleanly'
assert_eq "${CALLS[*]}" install 'interactive menu option 1 should call install'
assert_eq "$menu_count" 2 'interactive menu should redraw after install and exit'
assert_eq "$menu_response_index" 3 'interactive menu should consume install, continue and exit input'
printf 'PASS: interactive menu loops after an action and exits on 0\n'

for command_name in install start stop restart status port update log uninstall; do
    reset_calls
    case "$command_name" in
        install) cmd_install ;;
        start) cmd_start ;;
        stop) cmd_stop ;;
        restart) cmd_restart ;;
        status) cmd_status ;;
        port) cmd_port 12345 ;;
        update) cmd_update ;;
        log) cmd_log ;;
        uninstall) cmd_uninstall ;;
    esac
    assert_eq "${CALLS[*]}" "$command_name" "CLI command $command_name compatibility"
done
printf 'PASS: existing CLI command handlers remain available\n'

printf '\nMenu dispatch tests passed.\n'
