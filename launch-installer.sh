#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
if [[ ${1:-} == --cli ]]; then
    shift
    exec bash "$ST_DIR/storytold-installer.sh" "$@"
fi
[[ -n ${DISPLAY:-}${WAYLAND_DISPLAY:-} ]] || fail 'No graphical session. Use --cli --apps wordcraft (see README).'
if ! command -v zenity >/dev/null; then
    printf 'Installing Zenity for the graphical installer. Authentication may be requested.\n'
    admin /usr/bin/apt-get update
    admin /usr/bin/apt-get install -y zenity
fi
exec bash "$ST_DIR/storytold-gui.sh"
