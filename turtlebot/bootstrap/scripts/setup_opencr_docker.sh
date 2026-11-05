#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh" "$@"
OPENCR_STATE=/var/lib/turtlebot/bootstrap-opencr.conf
if [[ "${1:-pinned}" == --not-pinned ]]; then
  log "Resolving bootstrap v$BOOTSTRAP_VERSION; export after checking the bot"
else
  log "Using bootstrap v$BOOTSTRAP_VERSION snapshot"
fi

# target: Raspberry Pi OS Lite Trixie, 64-bit (arm64), TurtleBot3 ROS 2
# run as your normal user; this script invokes sudo where necessary
(( EUID != 0 )) || die "Run as your normal user (not with sudo)."
ARCH="$(dpkg --print-architecture)"
[[ "$ARCH" == "$TARGET_ARCH" ]] || die "Expected architecture: $TARGET_ARCH"
source /etc/os-release
[[ "${VERSION_CODENAME:-}" == "$TARGET_CODENAME" ]] || die "Expected OS release: $TARGET_CODENAME"

case "$OPENCR_MODEL" in
  burger|waffle) ;;
  *) die "OPENCR_MODEL must be burger or waffle." ;;
esac

command -v sudo >/dev/null || die "sudo is required."
sudo -v

log "Installing prerequisites"
sudo dpkg --add-architecture armhf
sudo apt-get update
sudo apt-get install -y -- "${PREREQUISITE_PACKAGES[@]}"

log "Removing conflicting Docker packages, if present"
CONFLICTS=()
for pkg in docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc; do
  if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" == 'install ok installed' ]]; then
    CONFLICTS+=("$pkg")
  fi
done
if (( ${#CONFLICTS[@]} )); then
  sudo apt-get remove -y "${CONFLICTS[@]}"
fi

log "Setting up the official Docker Debian repository"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $VERSION_CODENAME
Components: stable
Architectures: $ARCH
Signed-By: /etc/apt/keyrings/docker.asc
EOF

log "Installing Docker Engine, Compose, Buildx and Vim"
sudo apt-get update
sudo apt-get install -y -- "${DOCKER_PACKAGES[@]}"

if [[ -d /run/systemd/system ]]; then
  sudo systemctl enable --now docker
fi
sudo groupadd -f docker
sudo usermod -aG docker "$(id -un)"

log "Docker installed; checking versions"
docker --version
docker compose version

log "Downloading ROS 2 OpenCR firmware ($OPENCR_MODEL)"
if [[ ! "$OPENCR_REF" =~ ^[0-9a-f]{40}$ ]]; then
  OPENCR_REF="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/ROBOTIS-GIT/OpenCR-Binaries/commits/$OPENCR_REF")"
fi
[[ "$OPENCR_REF" =~ ^[0-9a-f]{40}$ ]] || die "Expected an OpenCR commit hash."
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT
wget -q --show-progress -O "$WORK_DIR/opencr_update.tar.bz2" \
  "https://raw.githubusercontent.com/ROBOTIS-GIT/OpenCR-Binaries/$OPENCR_REF/turtlebot3/ROS2/latest/opencr_update.tar.bz2"
ARCHIVE_SHA256="$(sha256sum "$WORK_DIR/opencr_update.tar.bz2")"
ARCHIVE_SHA256="${ARCHIVE_SHA256%% *}"
[[ -z "$OPENCR_SHA256" || "$ARCHIVE_SHA256" == "$OPENCR_SHA256" ]] || die "OpenCR archive checksum mismatch."
tar -xf "$WORK_DIR/opencr_update.tar.bz2" -C "$WORK_DIR"
[[ -x "$WORK_DIR/opencr_update/update.sh" ]] || die "OpenCR updater missing from archive."
[[ -f "$WORK_DIR/opencr_update/$OPENCR_MODEL.opencr" ]] || die "Firmware for $OPENCR_MODEL missing."
[[ -c "$OPENCR_PORT" ]] || die "Connect the OpenCR via USB; serial device missing: $OPENCR_PORT"

log "Flashing OpenCR on $OPENCR_PORT"
sudo rm -f -- "$OPENCR_STATE"
if ! (
  cd "$WORK_DIR/opencr_update"
  if [[ -w "$OPENCR_PORT" ]]; then
    ./update.sh "$OPENCR_PORT" "$OPENCR_MODEL.opencr"
  else
    sudo ./update.sh "$OPENCR_PORT" "$OPENCR_MODEL.opencr"
  fi
); then
  printf '\nOpenCR upload failed. To enter recovery mode:\n' >&2
  printf '  Hold PUSH SW2 -> press RESET -> release RESET -> release PUSH SW2.\n' >&2
  die "After the STATUS LED starts blinking, rerun the script."
fi

# export must describe the archive actually flashed, not a later upstream build
printf 'BOOTSTRAP_VERSION=%s\nOPENCR_REF=%s\nOPENCR_SHA256=%s\n' \
  "$BOOTSTRAP_VERSION" "$OPENCR_REF" "$ARCHIVE_SHA256" \
  > "$WORK_DIR/bootstrap-opencr.conf"
sudo install -D -m 0644 "$WORK_DIR/bootstrap-opencr.conf" "$OPENCR_STATE"

log "All software installed and OpenCR firmware flashed successfully"
printf '\nLog out and back in to use Docker without sudo.\n'
printf '\nFINAL MANUAL STEP — OPENCR TEST:\n'
printf '  1. Place the TurtleBot3 on flat ground with at least 1 metre clearance.\n'
printf '  2. Power on the OpenCR (red POWER LED should light).\n'
printf '  3. Hold PUSH SW1 for a few seconds: robot should travel about 30 cm.\n'
printf '  4. Hold PUSH SW2 for a few seconds: robot should rotate about 180 degrees.\n'
printf '\nFollow the ROBOTIS instructions:\n'
printf 'https://docs.robotis.com/docs/systems/turtlebot3/quick_start_guide/opencr_setup/?ros=humble#opencr-test\n'
