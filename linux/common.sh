#!/usr/bin/env bash
# Shared by the launcher, GUI and backend. Bash 4+.
# shellcheck disable=SC2034 # Used by the scripts sourcing this library.
ST_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
check_platform() {
    [[ $(uname -s) == Linux ]] || fail 'Run this installer on Linux.'
    [[ $EUID -ne 0 ]] || fail 'Run as your normal desktop user, not root.'
    [[ -r /etc/os-release ]] || fail '/etc/os-release is missing.'
    # shellcheck disable=SC1091
    . /etc/os-release
    case "$ID" in ubuntu|linuxmint|debian) ;; *) fail "Unsupported distribution: $ID" ;; esac
    case "$(uname -m)" in x86_64|aarch64) ;; *) fail 'Only native x86_64 and aarch64 are enabled.' ;; esac
    command -v apt-get >/dev/null || fail 'apt-get is required.'
}
admin() {
    if [[ -t 0 ]] && command -v sudo >/dev/null; then
        sudo -- "$@"
    elif command -v pkexec >/dev/null; then
        pkexec "$@"
    else
        fail 'Open a terminal and rerun with sudo installed, or install a PolicyKit authentication agent.'
    fi
}
check_path() {
    [[ $1 == /* && $1 != *$'\n'* && $1 != *$'\r'* && $1 != *$'\t'* ]] || fail "Expected an absolute path without control characters: $1"
}
