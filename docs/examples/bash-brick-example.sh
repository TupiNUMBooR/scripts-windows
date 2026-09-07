#!/usr/bin/env bash
set -Eeuo pipefail
# bash-brick-example.sh

SCRIPT_NAME="$(basename "$0")"

# required environment
EXAMPLE_VALUE="${EXAMPLE_VALUE:-}"

# optional environment
VERBOSE="${VERBOSE:-0}"


main() {
  handle_help "$@"

  [[ $# -eq 1 ]] || error 2 "Expected message"

  : "${EXAMPLE_VALUE:?EXAMPLE_VALUE is required}"

  need_commands jq curl

  local message="$1"

  [[ -n "${message//[[:space:]]/}" ]] \
    || error 65 "Message is empty"

  if [[ "$VERBOSE" == "1" ]]; then
    log "echo: example_value=$EXAMPLE_VALUE chars=${#message}"
  fi

  printf '%s\n' "$message"
}

usage() {
  cat <<EOF
$SCRIPT_NAME — example Bash brick that prints a message.

Usage:
  $SCRIPT_NAME <message>
  $SCRIPT_NAME -h|--help

Arguments:
  message  Text to print to standard output.

Environment:
  EXAMPLE_VALUE  Required example value.
  VERBOSE        Enable informational logs. Default: 0

Exit codes:
  # Standard exit codes.
  0    Completed successfully.
  2    Invalid command-line arguments.
  65   Invalid input data.
  66   Required input is missing.
  69   External service is unavailable.
  78   Invalid project configuration.
  127  Required command is unavailable.

  # Project-specific exit codes.
  12   A long-running local command failed.
  13   A paid operation failed.
  14   The project must fail immediately.

  21   Output already exists.

Example:
  EXAMPLE_VALUE=example $SCRIPT_NAME "Hello, world!"

This script is an example Bash brick. Some documented exit codes and required
commands are included only to demonstrate the standard brick interface.
EOF
}


# region functions

handle_help() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi
}

log() {
  printf '[%s] [%s] %s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$SCRIPT_NAME" \
    "$*" >&2
}

warn() {
  log "[WARN] $*"
}

error() {
  local code="$1"
  shift

  log "[ERROR] $*"
  exit "$code"
}

need_commands() {
  local name

  for name in "$@"; do
    command -v "$name" >/dev/null 2>&1 \
      || error 127 "Missing executable: $name"
  done
}

# endregion


main "$@"
