#!/usr/bin/env bash

set -u

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$ROOT_DIR/main.c"
LOG_DIR="$ROOT_DIR/pa2_test_logs"
TMP_ROOT=""
WORK_DIR=""
BIN=""
LAST_OUT=""
PASS_COUNT=0
FAIL_COUNT=0

pass()
{
    printf 'PASS: %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail()
{
    printf 'FAIL: %s\n' "$1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_contains()
{
    local file="$1"
    local text="$2"
    local name="$3"

    if grep -Fq -- "$text" "$file"; then
        pass "$name"
    else
        fail "$name"
        printf '  expected to find: %s\n' "$text"
    fi
}

assert_not_contains()
{
    local file="$1"
    local text="$2"
    local name="$3"

    if grep -Fq -- "$text" "$file"; then
        fail "$name"
        printf '  unexpected text found: %s\n' "$text"
    else
        pass "$name"
    fi
}

assert_line()
{
    local file="$1"
    local text="$2"
    local name="$3"

    if grep -Fxq -- "$text" "$file"; then
        pass "$name"
    else
        fail "$name"
        printf '  expected exact output line: %s\n' "$text"
    fi
}

assert_promptless_line()
{
    local file="$1"
    local text="$2"
    local name="$3"

    if sed 's/shell322>//g' "$file" | grep -Fxq -- "$text"; then
        pass "$name"
    else
        fail "$name"
        printf '  expected exact output line after removing prompts: %s\n' "$text"
    fi
}

assert_regex()
{
    local file="$1"
    local regex="$2"
    local name="$3"

    if grep -Eq -- "$regex" "$file"; then
        pass "$name"
    else
        fail "$name"
        printf '  expected regex: %s\n' "$regex"
    fi
}

assert_file_absent()
{
    local path="$1"
    local name="$2"

    if [ ! -e "$path" ]; then
        pass "$name"
    else
        fail "$name"
        printf '  still exists: %s\n' "$path"
    fi
}

cleanup()
{
    if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
        rm -rf "$TMP_ROOT"
    fi
}

run_shell_case()
{
    local name="$1"
    local input="$2"
    local out="$TMP_ROOT/$name.out"
    local status

    (cd "$WORK_DIR" && printf '%s' "$input" | timeout 10s "$BIN" > "$out" 2>&1)
    status=$?
    LAST_OUT="$out"

    if [ "$status" -eq 0 ]; then
        pass "$name exits successfully"
    else
        fail "$name exits successfully"
        printf '  exit status: %d\n' "$status"
    fi
}

require_linux()
{
    local os_name

    os_name="$(uname -s 2>/dev/null || true)"
    if [ "$os_name" != "Linux" ]; then
        printf 'This script is intended to be run on Linux only.\n'
        printf 'Detected OS: %s\n' "${os_name:-unknown}"
        printf 'Copy main.c and test_pa2_linux.sh to your Linux machine, then run:\n'
        printf '  chmod +x test_pa2_linux.sh\n'
        printf '  ./test_pa2_linux.sh\n'
        exit 2
    fi
}

require_command()
{
    local command_name="$1"

    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf 'FAIL: required command not found: %s\n' "$command_name"
        case "$command_name" in
            gcc)
                printf 'On Ubuntu/Debian, install it with: sudo apt update && sudo apt install build-essential\n'
                ;;
            timeout)
                printf 'On Ubuntu/Debian, install it with: sudo apt update && sudo apt install coreutils\n'
                ;;
        esac
        exit 1
    fi
}

check_source_portability()
{
    local first_posix
    local first_include

    first_posix="$(grep -nE '^#define[[:space:]]+_POSIX_C_SOURCE' "$SOURCE" | head -n 1 | cut -d: -f1)"
    first_include="$(grep -nE '^#include[[:space:]]+' "$SOURCE" | head -n 1 | cut -d: -f1)"

    if [ -n "$first_posix" ] && [ -n "$first_include" ] && [ "$first_posix" -lt "$first_include" ]; then
        pass "_POSIX_C_SOURCE is defined before headers"
    else
        fail "_POSIX_C_SOURCE is defined before headers"
    fi

    if grep -Eq '(^|[^[:alnum:]_])system[[:space:]]*\(' "$SOURCE"; then
        fail "source does not call system()"
    else
        pass "source does not call system()"
    fi

    for call in chdir getcwd setenv mkdir rmdir fork execvp pipe dup2 waitpid; do
        if grep -Eq "$call[[:space:]]*\\(" "$SOURCE"; then
            pass "source uses $call()"
        else
            fail "source uses $call()"
        fi
    done
}

compile_program()
{
    if gcc -std=c11 -Wall -Wextra -Werror -pedantic "$SOURCE" -o "$BIN"; then
        pass "gcc strict Linux-style build"
    else
        fail "gcc strict Linux-style build"
        exit 1
    fi
}

test_builtin_commands()
{
    local input
    local d

    input=$'pwd\n'
    input+=$'mkdir d1 d2 d3 d4 d5 d6 d7 d8 d9 d10\n'
    input+=$'rmdir d1\nrmdir d2\nrmdir d3\nrmdir d4\nrmdir d5\n'
    input+=$'rmdir d6\nrmdir d7\nrmdir d8\nrmdir d9\nrmdir d10\n'
    input+=$'mkdir rel_cd\ncd rel_cd\npwd\ncd ..\nrmdir rel_cd\n'
    input+="cd $WORK_DIR"$'\npwd\n'
    input+=$'printenv PWD\n'
    input+=$'cd\npwd\nexit\n'

    run_shell_case "builtins" "$input"

    assert_promptless_line "$LAST_OUT" "$WORK_DIR" "pwd prints current directory"
    assert_promptless_line "$LAST_OUT" "$WORK_DIR/rel_cd" "cd supports relative paths"
    assert_promptless_line "$LAST_OUT" "$WORK_DIR" "cd updates PWD for child commands"
    assert_promptless_line "$LAST_OUT" "${HOME:-}" "cd with no argument moves to HOME"

    for d in d1 d2 d3 d4 d5 d6 d7 d8 d9 d10 rel_cd; do
        assert_file_absent "$WORK_DIR/$d" "rmdir removed $d"
    done

    if [ "$(sed -n '1p' "$LAST_OUT")" = "" ]; then
        pass "output starts with empty line before prompt"
    else
        fail "output starts with empty line before prompt"
    fi
}

test_history_fifo()
{
    local input
    local i

    input=$'pwd\ncd .\n'
    for i in 3 4 5 6 7 8 9 10 11; do
        input+="echo h$i"$'\n'
    done
    input+=$'history\nexit\n'

    run_shell_case "history_fifo" "$input"

    assert_promptless_line "$LAST_OUT" "[1] echo h3" "history drops oldest command after capacity"
    assert_promptless_line "$LAST_OUT" "[2] echo h4" "history keeps issue order"
    assert_promptless_line "$LAST_OUT" "[9] echo h11" "history keeps ninth visible command"
    assert_promptless_line "$LAST_OUT" "[10] history" "history includes itself"
    assert_not_contains "$LAST_OUT" "[1] pwd" "history no longer contains first command"
}

test_external_background_pipe_and()
{
    local input

    input=$'echo EXTERNAL_OK\n'
    input+=$'sleep 1 &\n'
    input+=$'echo AFTER_BACKGROUND\n'
    input+=$'printf abcd | wc -c\n'
    input+=$'false && echo BAD_AND\n'
    input+=$'true && echo GOOD_AND\n'
    input+=$'exit\n'

    run_shell_case "external_background_pipe_and" "$input"

    assert_contains "$LAST_OUT" "EXTERNAL_OK" "external command runs through execvp"
    assert_regex "$LAST_OUT" 'shell322>[0-9]+' "background command prints child pid"
    assert_contains "$LAST_OUT" "AFTER_BACKGROUND" "shell continues after background command"
    assert_regex "$LAST_OUT" '(^|[^0-9])4([^0-9]|$)' "single pipe connects printf to wc"
    assert_not_contains "$LAST_OUT" "BAD_AND" "logical AND skips right command on failure"
    assert_contains "$LAST_OUT" "GOOD_AND" "logical AND runs right command on success"
}

test_error_handling()
{
    local input

    input=$'mkdir e1 e2 e3 e4 e5 e6 e7 e8 e9 e10 e11\n'
    input+=$'rmdir\n'
    input+=$'cd definitely_missing_directory\n'
    input+=$'exit\n'

    run_shell_case "error_handling" "$input"

    assert_contains "$LAST_OUT" "mkdir: at most 10 directories are allowed" "mkdir rejects more than ten directories"
    assert_contains "$LAST_OUT" "rmdir: exactly one directory name is required" "rmdir rejects missing operand"
    assert_contains "$LAST_OUT" "cd: No such file or directory" "cd reports missing directory"
}

main()
{
    require_linux

    if [ ! -f "$SOURCE" ]; then
        printf 'FAIL: main.c was not found next to this test script\n'
        exit 1
    fi

    require_command gcc
    require_command grep
    require_command sed
    require_command mktemp
    require_command timeout

    TMP_ROOT="$(mktemp -d /tmp/pa2_shell_test.XXXXXX)" || exit 1
    WORK_DIR="$TMP_ROOT/work"
    BIN="$TMP_ROOT/shell322_test"
    mkdir -p "$WORK_DIR"
    trap cleanup EXIT

    check_source_portability
    compile_program
    test_builtin_commands
    test_history_fifo
    test_external_background_pipe_and
    test_error_handling

    printf '\nSummary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"

    if [ "$FAIL_COUNT" -eq 0 ]; then
        printf 'All PA-2 checks passed.\n'
        exit 0
    fi

    rm -rf "$LOG_DIR"
    mkdir -p "$LOG_DIR"
    cp "$TMP_ROOT"/*.out "$LOG_DIR"/ 2>/dev/null || true
    printf 'At least one PA-2 check failed. Output logs were copied to: %s\n' "$LOG_DIR"
    exit 1
}

main "$@"
