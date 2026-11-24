#!/usr/bin/env bash
# Link the launcher, the sync script, the desktop entry and the systemd user
# timer into place. Re-run after pulling changes; everything is symlinked.
set -euo pipefail
here="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
config="${XDG_CONFIG_HOME:-$HOME/.config}"

for tool in quickshell magick ffmpeg ffprobe jq wl-copy; do
  command -v "$tool" >/dev/null || { echo "missing: $tool (pacman -S quickshell imagemagick libheif ffmpeg jq wl-clipboard)" >&2; exit 1; }
done
# HEIC, the iPhone's photo format, reaches ImageMagick through libheif, which
# the imagemagick package only lists as optional. Captured first: grep -q
# closing the pipe early would fail the pipeline under pipefail.
magick_formats=$(magick -list format 2>/dev/null || true)
if ! grep -qiE '^\s*HEIC\*?\s' <<< "$magick_formats"; then
  echo "missing: HEIC support in ImageMagick (pacman -S libheif)" >&2
  exit 1
fi

# icloudpd: the AUR package if you have it, otherwise the release binary goes
# into ~/.local/bin so nothing here needs root. That copy is this script's
# own, so a run after a git pull replaces it when it is older than
# ICLOUDPD_VERSION. An AUR package is left to pacman.
ICLOUDPD_VERSION=1.34.0
own_icloudpd="$HOME/.local/bin/icloudpd"
icloudpd_version() { "$1" --version 2>/dev/null | sed -n 's/^version:\([0-9.]*\).*/\1/p'; }
older_than_pin() { [ "$(printf '%s\n%s\n' "$1" "$ICLOUDPD_VERSION" | sort -V | head -1)" != "$ICLOUDPD_VERSION" ]; }
found_icloudpd="$(command -v icloudpd || true)"
if [ -n "$found_icloudpd" ] && [ "$(readlink -f "$found_icloudpd")" != "$(readlink -f "$own_icloudpd")" ]; then
  if older_than_pin "$(icloudpd_version "$found_icloudpd")"; then
    echo "note: $found_icloudpd is older than icloudpd $ICLOUDPD_VERSION; update it, or syncing stops while iCloud reports the library as being indexed" >&2
  fi
elif [ ! -x "$own_icloudpd" ] || older_than_pin "$(icloudpd_version "$own_icloudpd")"; then
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    *) echo "no icloudpd binary for $(uname -m); install the AUR package icloudpd-bin" >&2; exit 1 ;;
  esac
  mkdir -p "$HOME/.local/bin"
  echo "downloading icloudpd $ICLOUDPD_VERSION…"
  # Under a temporary name first, so a failed download keeps the old one.
  curl -fsSL -o "$own_icloudpd.tmp" \
    "https://github.com/icloud-photos-downloader/icloud_photos_downloader/releases/download/v$ICLOUDPD_VERSION/icloudpd-$ICLOUDPD_VERSION-linux-$arch" \
    || { rm -f "$own_icloudpd.tmp"; echo "could not download icloudpd $ICLOUDPD_VERSION" >&2; exit 1; }
  chmod +x "$own_icloudpd.tmp"
  mv "$own_icloudpd.tmp" "$own_icloudpd"
fi

# Installs from before the rename (everything was called icloud-recent) move
# over: config and cache keep their contents, the old links and units go.
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
if [ -d "$config/icloud-recent" ] && [ ! -d "$config/omarchy-icloud-photos" ]; then
  mv "$config/icloud-recent" "$config/omarchy-icloud-photos"
fi
if [ -d "$cache/icloud-recent" ] && [ ! -d "$cache/omarchy-icloud-photos" ]; then
  mv "$cache/icloud-recent" "$cache/omarchy-icloud-photos"
fi
if [ -d "$cache/icloud-recent-demo" ] && [ ! -d "$cache/omarchy-icloud-photos-demo" ]; then
  mv "$cache/icloud-recent-demo" "$cache/omarchy-icloud-photos-demo"
fi
if [ -e "$config/systemd/user/icloud-recent-sync.timer" ]; then
  systemctl --user disable --now icloud-recent-sync.timer 2>/dev/null || true
  rm -f "$config/systemd/user/icloud-recent-sync.timer" "$config/systemd/user/icloud-recent-sync.service"
fi
rm -f "$HOME/.local/bin/icloud-recent" "$HOME/.local/bin/icloud-recent-sync" "$HOME/.local/share/applications/icloud-recent.desktop"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications" "$config/systemd/user" "$config/omarchy-icloud-photos"
ln -sf "$here/bin/omarchy-icloud-photos" "$HOME/.local/bin/omarchy-icloud-photos"
ln -sf "$here/bin/omarchy-icloud-photos-sync" "$HOME/.local/bin/omarchy-icloud-photos-sync"
# The desktop entry is copied, not linked, so the icon can get its absolute
# path. LAUNCHER_NAME in the config renames it in the app launcher.
LAUNCHER_NAME=""
[ -f "$config/omarchy-icloud-photos/config" ] && . "$config/omarchy-icloud-photos/config"
sed "s|@ICON@|$here/assets/icon.png|; s|^Name=.*|Name=${LAUNCHER_NAME:-Omarchy iCloud Photos}|" "$here/omarchy-icloud-photos.desktop" > "$HOME/.local/share/applications/omarchy-icloud-photos.desktop"
ln -sf "$here/systemd/omarchy-icloud-photos-sync.service" "$config/systemd/user/omarchy-icloud-photos-sync.service"
ln -sf "$here/systemd/omarchy-icloud-photos-sync.timer" "$config/systemd/user/omarchy-icloud-photos-sync.timer"

if [ ! -f "$config/omarchy-icloud-photos/config" ]; then
  cat > "$config/omarchy-icloud-photos/config" <<CFG
# omarchy-icloud-photos configuration, sourced by omarchy-icloud-photos-sync
# APPLE_ID is filled in by the sign-in card in the app.
LIBRARY=\$HOME/Pictures/iCloud
CFG
  echo "Start omarchy-icloud-photos and sign in with your Apple ID."
fi

# The trash helper talks to iCloud through pyicloud, which comes with the
# icloudpd sources. It lives in a virtualenv inside the repository.
# icloudpd's Python sources want 3.11 up to 3.13 here. Use the system python
# when it fits, otherwise a 3.13 from mise (installed on demand, no root needed).
python_ok() { "$1" -c 'import sys; sys.exit(0 if (3, 11) <= sys.version_info[:2] <= (3, 13) else 1)' 2>/dev/null; }
# A virtualenv from an older install can sit on a python the pinned icloudpd
# no longer runs on (1.34 dropped 3.10); it only holds icloudpd, so it is
# simply made again.
if [ -x "$here/.venv/bin/python" ] && ! python_ok "$here/.venv/bin/python"; then
  echo "making the iCloud helper's virtualenv again for icloudpd $ICLOUDPD_VERSION…"
  rm -rf "$here/.venv"
fi
if [ ! -x "$here/.venv/bin/python" ]; then
  py=""
  for cand in python3 "$HOME"/.local/share/mise/installs/python/3.13*/bin/python3 "$HOME"/.local/share/mise/installs/python/3.12*/bin/python3; do
    if command -v "$cand" >/dev/null && python_ok "$cand"; then py="$cand"; break; fi
  done
  if [ -z "$py" ] && command -v mise >/dev/null; then
    echo "installing python 3.13 with mise for the iCloud helper…"
    mise install python@3.13 >/dev/null
    py="$(mise where python@3.13)/bin/python3"
  fi
  [ -n "$py" ] && python_ok "$py" || { echo "need a python between 3.11 and 3.13 for the iCloud helper (mise install python@3.13)" >&2; exit 1; }
  "$py" -m venv "$here/.venv"
fi
# The helper's pyicloud follows the same pin as the icloudpd binary, also in
# a virtualenv an earlier install made.
venv_icloudpd="$("$here/.venv/bin/python" -c 'import importlib.metadata as m; print(m.version("icloudpd"))' 2>/dev/null || true)"
if [ "$venv_icloudpd" != "$ICLOUDPD_VERSION" ]; then
  echo "installing icloudpd $ICLOUDPD_VERSION for the iCloud helper…"
  "$here/.venv/bin/pip" install -q --upgrade "git+https://github.com/icloud-photos-downloader/icloud_photos_downloader@v$ICLOUDPD_VERSION" piexif
fi

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable --now omarchy-icloud-photos-sync.timer
echo "installed; next sync: $(systemctl --user list-timers omarchy-icloud-photos-sync.timer --no-pager | sed -n 2p | awk '{print $1, $2, $3}')"
