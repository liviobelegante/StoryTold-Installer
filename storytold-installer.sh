#!/usr/bin/env bash
set -Eeuo pipefail
# shellcheck source=common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/common.sh"
usage() {
    cat <<'EOF'
Usage: bash storytold-installer.sh --apps wordcraft,gridcraft [options]
  --apps LIST    Comma-separated IDs, or all (required)
  --jobs N       Parallel compiler jobs (default 2)
  --desktop      Also copy .desktop entries to the XDG Desktop directory
  --dry-run      Print pinned sources and apt packages without changing anything
  --allow-sleep  Explicitly permit a build without systemd sleep inhibition
  --help        Show this help
EOF
}
apps='' jobs=2 desktop=0 dry=0 allow_sleep=0
original=("$@")
while (( $# )); do
    case "$1" in
        --apps) [[ $# -ge 2 ]] || fail '--apps needs a value'; apps=$2; shift 2 ;;
        --jobs) [[ $# -ge 2 ]] || fail '--jobs needs a value'; jobs=$2; shift 2 ;;
        --desktop) desktop=1; shift ;;
        --dry-run) dry=1; shift ;;
        --allow-sleep) allow_sleep=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
done
[[ -n $apps ]] || { usage; exit 2; }
[[ $jobs =~ ^[1-9][0-9]*$ ]] || fail '--jobs must be positive.'
# Validate before requesting privileges or installing packages.
[[ $apps != all ]] || apps=wordcraft,gridcraft,deckcraft,pdfcraft,cadcraft,solidcraft
[[ $apps != ,* && $apps != *, && $apps != *,,* ]] || fail 'Empty app ID.'
IFS=, read -r -a selected <<< "$apps"
declare -A seen=()
for app in "${selected[@]}"; do
    case "$app" in wordcraft|gridcraft|deckcraft|pdfcraft|cadcraft|solidcraft) ;; *) fail "Unknown app: $app" ;; esac
    [[ -z ${seen[$app]:-} ]] || fail "Duplicate app: $app"
    seen[$app]=1
done
if (( dry )); then
    command -v python3 >/dev/null || fail 'python3 is needed for --dry-run.'
    exec python3 "$ST_DIR/support.py" plan "$ST_DIR/apps.json" "$apps"
fi
check_platform
if (( ! allow_sleep )) && [[ ${STORYTOLD_INHIBITED:-} != 1 ]]; then
    command -v systemd-inhibit >/dev/null || fail 'systemd-inhibit is missing. Install systemd or explicitly use --allow-sleep.'
    # If logind denies inhibition, fail; do not silently fall back to an unprotected build.
    exec systemd-inhibit --what=sleep:idle --mode=block --who='StoryTold Installer' \
        --why='Compiling selected Craft applications' \
        env STORYTOLD_INHIBITED=1 bash "$ST_DIR/storytold-installer.sh" "${original[@]}"
fi
state=${XDG_STATE_HOME:-$HOME/.local/state}/storytold
cache=${XDG_CACHE_HOME:-$HOME/.cache}/storytold
data=${XDG_DATA_HOME:-$HOME/.local/share}
for path in "$state" "$cache" "$data"; do check_path "$path"; done
mkdir -p "$state/logs" "$cache" "$data/storytold"
command -v flock >/dev/null || fail 'flock (util-linux) is required.'
exec 9>"$state/installer.lock"
flock -n 9 || fail 'Another StoryTold installation is already running.'
log=$(mktemp "$state/logs/install-XXXXXXXX.log")
exec > >(tee -a "$log") 2>&1
on_error() {
    local rc=$1 line=$2
    printf 'Installation stopped at line %s (exit %s). Log: %s\n' "$line" "$rc" "$log" >&2
    exit "$rc"
}
trap 'on_error "$?" "$LINENO"' ERR
printf 'Log: %s\nSelected apps: %s\n' "$log" "$apps"
(( ! allow_sleep )) || printf 'WARNING: sleep prevention explicitly disabled.\n'
admin /usr/bin/apt-get update
admin /usr/bin/apt-get install -y --no-install-recommends \
    build-essential git curl ca-certificates python3 pkg-config cmake \
    desktop-file-utils xdg-user-dirs xdg-utils util-linux fonts-dejavu-core \
    libvulkan1 mesa-vulkan-drivers
packages=$(python3 "$ST_DIR/support.py" packages "$ST_DIR/apps.json" "$apps")
read -r -a apt_packages <<< "$packages"
# Simulate first: unavailable packages fail before app-specific dependencies are changed.
/usr/bin/apt-get -s install --no-install-recommends "${apt_packages[@]}"
admin /usr/bin/apt-get install -y --no-install-recommends "${apt_packages[@]}"
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
if ! command -v rustup >/dev/null; then
    curl --proto '=https' --tlsv1.2 --fail --location --retry 3 \
        https://sh.rustup.rs -o "$cache/rustup-init.sh"
    sh "$cache/rustup-init.sh" -y --profile minimal --default-toolchain none --no-modify-path
fi
rustup toolchain install stable --profile minimal
rustc +stable --version
cargo +stable --version
host=$(rustc +stable -vV | sed -n 's/^host: //p')
[[ $host == *-unknown-linux-gnu ]] || fail "Unexpected native Rust target: $host"
# Cargo checks each package's declared MSRV; never fall back to old distro Rust.
export RUSTFLAGS='-C target-cpu=native'
unset CARGO_ENCODED_RUSTFLAGS CARGO_BUILD_TARGET RUSTC_WRAPPER RUSTC_WORKSPACE_WRAPPER
unset CRAFT_FONTS_DIR CRAFT_FONTS_REQUIRED
environment=$( { rustc +stable -vV; cat /etc/os-release; \
    LC_ALL=C lscpu | grep -E '^(Architecture|Byte Order|Vendor ID|Model name|CPU family|Model:|Stepping|Flags|Features)'; \
    dpkg-query -W -f='${Package}=${Version}\n'; } | sha256sum | cut -d' ' -f1)
for app in "${selected[@]}"; do
    row=$(python3 "$ST_DIR/support.py" row "$ST_DIR/apps.json" "$app")
    IFS=$'\t' read -r repo commit package binary <<< "$row"
    src="$cache/sources/$app/$commit"
    printf '\n=== %s @ %s ===\n' "$repo" "$commit"
    if [[ ! -d $src/.git ]]; then
        [[ ! -e $src ]] || fail "Incomplete checkout: move aside $src and retry."
        mkdir -p "$src"
        git -C "$src" init
        git -C "$src" remote add origin "https://github.com/$repo.git"
    fi
    # Resume a previously interrupted fetch without resetting modified source files.
    if ! git -C "$src" rev-parse --verify HEAD >/dev/null 2>&1; then
        git -C "$src" fetch --depth 1 origin "$commit"
        git -C "$src" checkout --detach "$commit"
    fi
    [[ $(git -C "$src" rev-parse HEAD) == "$commit" ]] || fail "Unexpected revision in $src"
    [[ -z $(git -C "$src" status --porcelain --untracked-files=normal) ]] || fail "Modified checkout: $src"
    [[ -f $src/Cargo.lock ]] || fail "Missing Cargo.lock in $src"
    export CARGO_TARGET_DIR="$cache/targets/$app/$environment"
    mkdir -p "$CARGO_TARGET_DIR"
    (
        cd "$src"
        # Always ask Cargo to validate freshness. This reuses valid artifacts and resumes failed builds.
        cargo +stable build --release --locked --jobs "$jobs" --target "$host" -p "$package" --bin "$binary"
    )
    built="$CARGO_TARGET_DIR/$host/release/$binary"
    [[ -x $built ]] || fail "Expected executable missing: $built"
    linkage=$(ldd "$built" 2>&1) || fail "Cannot inspect runtime libraries for $built"
    printf '%s\n' "$linkage"
    [[ $linkage != *'not found'* ]] || fail "Runtime library missing for $app"
    dest="$data/storytold/apps/$app"
    mkdir -p "$dest"
    install -m 755 "$built" "$dest/$binary.new"
    mv -f -- "$dest/$binary.new" "$dest/$binary"
    python3 "$ST_DIR/support.py" desktop "$data" "$app" "$dest/$binary" "$desktop"
    desktop-file-validate "$data/applications/storytold-$app.desktop"
    printf '%s\n' "$repo $commit" "$(rustc +stable --version)" "$RUSTFLAGS" \
        "environment=$environment" > "$dest/build-info.txt"
    printf 'Installed %s\n' "$app"
done
update-desktop-database "$data/applications"
printf '\nAll selected applications installed. Log: %s\n' "$log"
