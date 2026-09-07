#!/usr/bin/env bash
set -Eeuo pipefail
# test-bash-brick-example.sh

TEST_NAME="$(basename "$0")"
SCRIPT_NAME="${TEST_NAME#test-}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

LOCAL_SCRIPT="$SCRIPT_DIR/$SCRIPT_NAME"

if [[ -e "$LOCAL_SCRIPT" ]]; then
  SCRIPT_UNDER_TEST="$LOCAL_SCRIPT"
else
  PROJECT_DIR="${SCRIPT_DIR%%/test/*}"
  RELATIVE_DIR="${SCRIPT_DIR#"$PROJECT_DIR/test/"}"

  SCRIPT_UNDER_TEST="$PROJECT_DIR/src/$RELATIVE_DIR/$SCRIPT_NAME"
fi

PASS=0
FAIL=0
TMP_DIR=""


main() {
  need_commands bash jq curl mktemp grep

  [[ -x "$SCRIPT_UNDER_TEST" ]] \
    || error "Tested file not found or not executable: $SCRIPT_UNDER_TEST"

  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT

  run_test "help works without environment" test_help
  run_test "rejects missing arguments" test_missing_arguments
  run_test "rejects too many arguments" test_too_many_arguments
  run_test "requires EXAMPLE_VALUE" test_requires_example_value
  run_test "rejects empty message" test_empty_message
  run_test "rejects whitespace-only message" test_whitespace_message
  run_test "prints message" test_prints_message
  run_test "verbose logs details" test_verbose

  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"

  ((FAIL == 0))
}


# region tests

test_help() {
  run env -u EXAMPLE_VALUE "$SCRIPT_UNDER_TEST" --help

  assert_status 0
  assert_stdout_contains "Usage:"
  assert_stdout_contains "EXAMPLE_VALUE"
  assert_stderr_empty
}

test_missing_arguments() {
  run env EXAMPLE_VALUE=example "$SCRIPT_UNDER_TEST"

  assert_status 2
  assert_stderr_contains "Expected message"
}

test_too_many_arguments() {
  run env EXAMPLE_VALUE=example "$SCRIPT_UNDER_TEST" one two

  assert_status 2
  assert_stderr_contains "Expected message"
}

test_requires_example_value() {
  run env -u EXAMPLE_VALUE "$SCRIPT_UNDER_TEST" "hello"

  assert_status 1
  assert_stderr_contains "EXAMPLE_VALUE is required"
}

test_empty_message() {
  run env EXAMPLE_VALUE=example "$SCRIPT_UNDER_TEST" ""

  assert_status 65
  assert_stderr_contains "Message is empty"
}

test_whitespace_message() {
  run env EXAMPLE_VALUE=example "$SCRIPT_UNDER_TEST" "   "

  assert_status 65
  assert_stderr_contains "Message is empty"
}

test_prints_message() {
  run env EXAMPLE_VALUE=example "$SCRIPT_UNDER_TEST" "Hello, world!"

  assert_status 0
  assert_stdout_equals "Hello, world!"
  assert_stderr_empty
}

test_verbose() {
  run env \
    EXAMPLE_VALUE=example \
    VERBOSE=1 \
    "$SCRIPT_UNDER_TEST" \
    "hello"

  assert_status 0
  assert_stdout_equals "hello"
  assert_stderr_contains "echo: example_value=example chars=5"
}

# endregion


# region test helpers

run_test() {
  local name="$1"
  local test_function="$2"

  if (
    "$test_function"
  ); then
    printf 'ok - %s\n' "$name"
    ((PASS += 1))
  else
    printf 'not ok - %s\n' "$name"
    ((FAIL += 1))
  fi
}

run() {
  STDOUT_FILE="$TMP_DIR/stdout"
  STDERR_FILE="$TMP_DIR/stderr"

  set +e
  "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  STATUS=$?
  set -e
}

assert_status() {
  local expected="$1"

  [[ "$STATUS" -eq "$expected" ]] \
    || fail "expected exit $expected, got $STATUS\nstderr:\n$(cat "$STDERR_FILE")"
}

assert_stdout_equals() {
  local expected="$1"
  local actual

  actual="$(cat "$STDOUT_FILE")"

  [[ "$actual" == "$expected" ]] \
    || fail "stdout mismatch\nexpected: $expected\nactual:   $actual"
}

assert_stdout_contains() {
  local expected="$1"

  grep -Fq -- "$expected" "$STDOUT_FILE" \
    || fail "stdout does not contain: $expected"
}

assert_stderr_contains() {
  local expected="$1"

  grep -Fq -- "$expected" "$STDERR_FILE" \
    || fail "stderr does not contain: $expected"
}

assert_stderr_empty() {
  [[ ! -s "$STDERR_FILE" ]] \
    || fail "stderr is not empty:\n$(cat "$STDERR_FILE")"
}

fail() {
  printf '  %b\n' "$*" >&2
  exit 1
}

error() {
  printf '[%s] [ERROR] %s\n' "$TEST_NAME" "$*" >&2
  exit 1
}

need_commands() {
  local name

  for name in "$@"; do
    command -v "$name" >/dev/null 2>&1 \
      || error "Missing executable: $name"
  done
}

# endregion


main "$@"
