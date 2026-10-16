#!/bin/bash
# TaskAlarm installer — the to-do list that cheers you on.
#
#   curl -fsSL https://raw.githubusercontent.com/maxlkatze/taskalarm/main/install.sh | bash
#
# Downloads the latest release into /Applications and launches it. If no release is
# available (or you pass --source), it builds from source instead (needs Xcode CLT).
set -euo pipefail

REPO="maxlkatze/taskalarm"
APP_NAME="TaskAlarm.app"
DEST="/Applications"

violet=$'\033[38;2;124;92;255m'; green=$'\033[38;2;52;199;123m'; amber=$'\033[38;2;255;176;32m'
red=$'\033[38;2;255;77;94m'; dim=$'\033[2m'; bold=$'\033[1m'; reset=$'\033[0m'
[[ -t 1 ]] || { violet=; green=; amber=; red=; dim=; bold=; reset=; }

step() { printf "  ${violet}▸${reset} %s\n" "$1"; }
ok()   { printf "  ${green}✓${reset} %s\n" "$1"; }
fail() { printf "\n  ${red}✗ %s${reset}\n\n" "$1" >&2; exit 1; }

printf "\n${violet}${bold}"
cat <<'ART'
     ▄▀▄     ▄▀▄
    ▄█▀▀█████▀▀█▄      TaskAlarm
   █   ●     ●   █     the to-do list that cheers you on
   █  ▀▄▄▄▄▄▄▄▀  █
    ▀▄▄       ▄▄▀
    ▄▀ ▀▀▀▀▀▀▀ ▀▄
ART
printf "${reset}\n"

[[ "$(uname -s)" == "Darwin" ]] || fail "TaskAlarm is a macOS app."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "TaskAlarm needs macOS 14 (Sonoma) or newer."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

build_from_source() {
    command -v swift >/dev/null 2>&1 || fail "No release found and Swift isn't installed. Run: xcode-select --install"
    step "Downloading the source…"
    curl -fsSL "https://github.com/$REPO/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP"
    step "Building (this takes a minute)…"
    (cd "$TMP"/taskalarm-main && ./scripts/build.sh >/dev/null)
    mv "$TMP"/taskalarm-main/build/"$APP_NAME" "$TMP/$APP_NAME"
}

if [[ "${1:-}" == "--source" ]]; then
    build_from_source
else
    step "Downloading the latest release…"
    if curl -fsSL "https://github.com/$REPO/releases/latest/download/TaskAlarm.zip" -o "$TMP/TaskAlarm.zip"; then
        ditto -x -k "$TMP/TaskAlarm.zip" "$TMP"
    else
        printf "  ${amber}!${reset} No release yet — building from source instead.\n"
        build_from_source
    fi
fi

[[ -d "$TMP/$APP_NAME" ]] || fail "Something went wrong: the app wasn't found in the download."

step "Installing to $DEST…"
if pgrep -x TaskAlarm >/dev/null; then
    osascript -e 'quit app "TaskAlarm"' >/dev/null 2>&1 || true
    sleep 1
    pkill -x TaskAlarm 2>/dev/null || true
fi
SUDO=""
[[ -w "$DEST" ]] || SUDO="sudo"
$SUDO rm -rf "$DEST/$APP_NAME"
$SUDO ditto "$TMP/$APP_NAME" "$DEST/$APP_NAME"
# The app is ad-hoc signed, not notarized: clear the download quarantine so it opens without a warning.
$SUDO xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true
ok "Installed $DEST/$APP_NAME"

step "Launching…"
open "$DEST/$APP_NAME"
ok "Done! Look for the smiley in your menu bar ${amber}☺${reset}"
printf "\n  ${dim}Your tasks live in ~/Library/Application Support/TaskAlarm. Uninstall: rm -rf $DEST/$APP_NAME${reset}\n\n"
