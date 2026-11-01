#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
check_platform
command -v zenity >/dev/null || fail 'Run launch-installer.sh first.'
selection=$(zenity --list --checklist --title='StoryTold Installer — Linux' --width=650 --height=390 \
    --text='Select desktop apps to build from verified source revisions.' \
    --column=Install --column=ID --column=Application --print-column=2 --separator=, \
    TRUE wordcraft WordCraft TRUE gridcraft GridCraft TRUE deckcraft DeckCraft \
    TRUE pdfcraft PDFCraft FALSE cadcraft CADCraft FALSE solidcraft SolidCraft) || exit 0
[[ -n $selection ]] || exit 0
jobs=$(zenity --entry --title='Build parallelism' --text='Parallel compiler jobs (1 uses less RAM):' --entry-text=2) || exit 0
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { zenity --error --text='Enter a positive integer.'; exit 2; }
zenity --question --width=600 --title='Install selected apps' \
    --text="Apps: $selection

Install apt dependencies, install/update the Rust stable toolchain, and compile release binaries optimized for this CPU.
Builds may take hours and substantial disk space. Existing build data is reused.
Sleep inhibition is required. Files go into your user account.

Closing the log window does not cancel installation. Continue?" || exit 0
desktop=()
if zenity --question --text='Also copy launchers to your Desktop folder?'; then desktop=(--desktop); fi
state=${XDG_STATE_HOME:-$HOME/.local/state}/storytold
check_path "$state"
mkdir -p "$state/logs"
log=$(mktemp "$state/logs/gui-XXXXXXXX.log")
bash "$ST_DIR/storytold-installer.sh" --apps "$selection" --jobs "$jobs" "${desktop[@]}" >"$log" 2>&1 &
worker=$!
tail --pid="$worker" -n +1 -f "$log" | zenity --text-info --title='StoryTold build log' --auto-scroll \
    --width=900 --height=600 --ok-label='Close log' &
viewer=$!
status=0
wait "$worker" || status=$?
kill "$viewer" 2>/dev/null || true
wait "$viewer" 2>/dev/null || true
if (( status == 0 )); then
    zenity --info --text="Installation completed. Apps are in your application menu.\nLog: $log"
else
    zenity --error --width=650 --text="Installation stopped (exit $status). Completed apps remain installed; rerun to reuse builds.\nLog: $log"
fi
exit "$status"
