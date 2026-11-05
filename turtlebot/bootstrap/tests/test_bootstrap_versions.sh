#!/usr/bin/env bash
set -Eeuo pipefail

BOOTSTRAP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf -- "$WORK_DIR"' EXIT
FIXTURE="$WORK_DIR/package with spaces"
FIXTURE_BOOTSTRAP="$FIXTURE/bootstrap"
mkdir -p "$FIXTURE_BOOTSTRAP/scripts" "$FIXTURE_BOOTSTRAP/etc"
cp "$BOOTSTRAP_DIR/scripts/config.sh" "$FIXTURE_BOOTSTRAP/scripts/"
cp "$BOOTSTRAP_DIR/etc/bootstrap-versions.conf" "$FIXTURE_BOOTSTRAP/etc/"
cp "$BOOTSTRAP_DIR/etc/bootstrap-versions.conf" "$WORK_DIR/unpinned.conf"
SNAPSHOT_FILE="$FIXTURE_BOOTSTRAP/etc/bootstrapped-versions-v1.0.0.conf"
SECOND_SNAPSHOT="$FIXTURE_BOOTSTRAP/etc/bootstrapped-versions-v2.0.0.conf"
STATE_FILE="$WORK_DIR/bootstrap-opencr.conf"
for script in export_versions.sh check_versions.sh; do
  sed "s|^OPENCR_STATE=.*|OPENCR_STATE=\"$STATE_FILE\"|" \
    "$BOOTSTRAP_DIR/scripts/$script" > "$FIXTURE_BOOTSTRAP/scripts/$script"
done
COMMIT="$(printf '%040d' 1)"
CHECKSUM="$(printf '%064d' 2)"
record() {
  printf 'BOOTSTRAP_VERSION=%s\nOPENCR_REF=%s\nOPENCR_SHA256=%s\n' \
    "$1" "$COMMIT" "${2:-$CHECKSUM}" > "$STATE_FILE"
}
record 1.0.0
unset BOOTSTRAP_VERSION OPENCR_PORT OPENCR_MODEL

# stub Linux metadata only; these checks never install packages or run Make
source() {
  if [[ "$1" == /etc/os-release ]]; then
    VERSION_CODENAME="${TEST_CODENAME:-trixie}"
  else
    builtin source "$@"
  fi
}
dpkg() { printf '%s\n' "${TEST_ARCH:-arm64}"; }
dpkg-query() {
  local package="${@: -1}"
  if [[ "$package" == "${TEST_MISSING_PACKAGE:-}" ]]; then
    printf 'config-files\t'
  else
    printf 'installed\t%s' "${TEST_VERSION:-1:2.3-4}"
  fi
}
docker() { [[ "${TEST_DOCKER_FAIL:-0}" == 0 ]]; }
export -f source dpkg dpkg-query docker

cd "$WORK_DIR"
bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh" > "$WORK_DIR/export.log"
builtin source "$SNAPSHOT_FILE"
[[ "$BOOTSTRAP_VERSION" == 1.0.0 ]]
for spec in "${PREREQUISITE_PACKAGES[@]}" "${DOCKER_PACKAGES[@]}"; do
  [[ "$spec" == *'=1:2.3-4' ]]
done
[[ "${PREREQUISITE_PACKAGES[4]}" == 'libc6:armhf=1:2.3-4' ]]
[[ "$OPENCR_REF" == "$COMMIT" && "$OPENCR_SHA256" == "$CHECKSUM" ]]
cp "$SNAPSHOT_FILE" "$WORK_DIR/saved.conf"
cmp -s "$FIXTURE_BOOTSTRAP/etc/bootstrap-versions.conf" "$WORK_DIR/unpinned.conf"
bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh" > "$WORK_DIR/check.log"

reject() {
  if "$@" > "$WORK_DIR/failure.log" 2>&1; then
    printf 'Expected failure: %s\n' "$*" >&2
    exit 1
  fi
  cmp -s "$SNAPSHOT_FILE" "$WORK_DIR/saved.conf"
}
reject bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
reject env TEST_MISSING_PACKAGE=curl bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
reject env TEST_VERSION=9.9 bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
reject env TEST_DOCKER_FAIL=1 bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
record 1.0.0 "$(printf '%064d' 3)"
reject bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
record 2.0.0
reject bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
reject env BOOTSTRAP_VERSION=2.0.0 TEST_MISSING_PACKAGE=curl bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
reject env BOOTSTRAP_VERSION=2.0.0 TEST_CODENAME=bookworm bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
reject env BOOTSTRAP_VERSION=2.0.0 TEST_ARCH=amd64 bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
rm -f -- "$STATE_FILE"
reject env BOOTSTRAP_VERSION=2.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
printf 'BOOTSTRAP_VERSION=2.0.0\nOPENCR_REF=%s\n' "$COMMIT" > "$STATE_FILE"
reject env BOOTSTRAP_VERSION=2.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh"
[[ ! -e "$SECOND_SNAPSHOT" ]]

record 2.0.0
BOOTSTRAP_VERSION=2.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/export_versions.sh" > "$WORK_DIR/export.log"
builtin source "$SECOND_SNAPSHOT"
[[ "$BOOTSTRAP_VERSION" == 2.0.0 ]]
cmp -s "$SNAPSHOT_FILE" "$WORK_DIR/saved.conf"
printf 'BOOTSTRAP_VERSION=2.0.0\n' > "$FIXTURE/.env"
bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh" > "$WORK_DIR/check.log"
reject env BOOTSTRAP_VERSION=1.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
reject env BOOTSTRAP_VERSION=3.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
cp "$SNAPSHOT_FILE" "$FIXTURE_BOOTSTRAP/etc/bootstrapped-versions-v3.0.0.conf"
reject env BOOTSTRAP_VERSION=3.0.0 bash "$FIXTURE_BOOTSTRAP/scripts/check_versions.sh"
printf 'Bootstrap version export and smoke checks passed.\n'
