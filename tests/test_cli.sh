#!/usr/bin/env bash
# These checks never run apt, rustup or a build.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
backend="$root/linux/storytold-installer.sh"
bash "$backend" --help >/dev/null
plan=$(bash "$backend" --apps all --dry-run)
[[ $(printf '%s\n' "$plan" | grep -c 'https://github.com/') == 6 ]]
[[ $plan == *'tangency-labs/solidcraft'* ]]
for selection in bogus 'wordcraft,wordcraft' 'wordcraft,' ',wordcraft' 'wordcraft,,gridcraft'; do
    if bash "$backend" --apps "$selection" --dry-run >/dev/null 2>&1; then
        printf 'Unexpected accepted selection: %s\n' "$selection" >&2
        exit 1
    fi
done
for jobs in 0 -1 invalid; do
    if bash "$backend" --apps wordcraft --jobs "$jobs" --dry-run >/dev/null 2>&1; then
        printf 'Unexpected accepted jobs: %s\n' "$jobs" >&2
        exit 1
    fi
done
if bash "$backend" --apps >/dev/null 2>&1; then exit 1; fi
if bash "$backend" --not-an-option >/dev/null 2>&1; then exit 1; fi
printf 'CLI validation checks passed.\n'
