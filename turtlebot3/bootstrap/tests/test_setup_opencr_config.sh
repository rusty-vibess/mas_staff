#!/usr/bin/env bash
set -Eeuo pipefail

BOOTSTRAP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT
FIXTURE="$WORK_DIR/package with spaces"
mkdir -p "$FIXTURE/bootstrap/scripts" "$FIXTURE/bootstrap/etc"
cp "$BOOTSTRAP_DIR/scripts/config.sh" "$FIXTURE/bootstrap/scripts/"
cp "$BOOTSTRAP_DIR/etc/bootstrap-version.conf" "$FIXTURE/bootstrap/etc/"
CONFIG_FILE="$FIXTURE/bootstrap/scripts/config.sh"
PROBE="$FIXTURE/bootstrap/scripts/probe.sh"
cat > "$PROBE" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
die() { printf '%s\n' "$*" >&2; exit 1; }
source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh" "$@"
[[ "$OPENCR_PORT|$OPENCR_MODEL|$BOOTSTRAP_VERSION" == "$EXPECTED_CONFIG" ]]
EOF
unset OPENCR_PORT OPENCR_MODEL BOOTSTRAP_VERSION EXPECTED_CONFIG
cd "$WORK_DIR"

check() {
  local expected="$1"
  shift
  EXPECTED_CONFIG="$expected" "$@"
}

reject_config() {
  if bash -c 'set -Eeuo pipefail; die() { exit 1; }; source "$1" "${@:2}"' _ "$CONFIG_FILE" "$@" > "$WORK_DIR/failure.log" 2>&1; then
    printf 'Invalid configuration unexpectedly succeeded\n' >&2
    exit 1
  fi
}

reject_config
check '/dev/ttyACM0|burger|1.0.1' bash "$PROBE" --not-pinned
check '/dev/terminal|waffle|1.0.1' env OPENCR_PORT=/dev/terminal OPENCR_MODEL=waffle bash "$PROBE" --not-pinned
: > "$FIXTURE/.env"
check '/dev/ttyACM0|burger|1.0.1' bash "$PROBE" --not-pinned
printf 'OPENCR_PORT="/dev/OpenCR USB"\nOPENCR_MODEL=waffle\n' > "$FIXTURE/.env"
check '/dev/OpenCR USB|waffle|1.0.1' bash "$PROBE" --not-pinned
check '/dev/OpenCR USB|burger|1.0.1' env OPENCR_MODEL=burger bash "$PROBE" --not-pinned
check '/dev/terminal|waffle|1.0.1' env OPENCR_PORT=/dev/terminal bash "$PROBE" --not-pinned
check '/dev/terminal|burger|1.0.1' env OPENCR_PORT=/dev/terminal OPENCR_MODEL=burger bash "$PROBE" --not-pinned
check '/dev/OpenCR USB|waffle|1.0.1' env OPENCR_PORT= OPENCR_MODEL= bash "$PROBE" --not-pinned
printf 'BOOTSTRAP_VERSION=1.2.0\n' > "$FIXTURE/.env"
check '/dev/ttyACM0|burger|1.2.0' bash "$PROBE" --not-pinned
check '/dev/ttyACM0|burger|2.0.0' env BOOTSTRAP_VERSION=2.0.0 bash "$PROBE" --not-pinned
BOOTSTRAP_VERSION=../escape reject_config --not-pinned
SNAPSHOT_FILE="$FIXTURE/bootstrap/etc/bootstrap-v1.2.0.conf"
printf 'BOOTSTRAP_VERSION=9.9.9\n' > "$SNAPSHOT_FILE"
reject_config
check '/dev/ttyACM0|burger|1.2.0' bash "$PROBE" --not-pinned
: > "$SNAPSHOT_FILE"
reject_config
printf 'BOOTSTRAP_VERSION=1.2.0\n' > "$SNAPSHOT_FILE"
reject_config
{
  printf 'BOOTSTRAP_VERSION=1.2.0\nTARGET_CODENAME=trixie\nTARGET_ARCH=arm64\n'
  printf 'PREREQUISITE_PACKAGES=(curl=1)\nDOCKER_PACKAGES=(vim=1)\n'
  printf 'OPENCR_REF=%040d\nOPENCR_SHA256=%064d\n' 1 2
} > "$SNAPSHOT_FILE"
check '/dev/ttyACM0|burger|1.2.0' bash "$PROBE"
reject_config --unknown
reject_config --not-pinned extra
rm -f -- "$SNAPSHOT_FILE"
printf 'OPENCR_MODEL=(\n' > "$FIXTURE/.env"
reject_config --not-pinned
printf 'OpenCR configuration checks passed.\n'
