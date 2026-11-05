#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh" --not-pinned
[[ ! -e "$SNAPSHOT_FILE" ]] || die "Snapshot already exists; choose a new BOOTSTRAP_VERSION."
source /etc/os-release
[[ "${VERSION_CODENAME:-}" == "$TARGET_CODENAME" ]] || die "Expected OS release: $TARGET_CODENAME"
[[ "$(dpkg --print-architecture)" == "$TARGET_ARCH" ]] || die "Expected architecture: $TARGET_ARCH"

OPENCR_STATE=/var/lib/turtlebot/bootstrap-opencr.conf
[[ -f "$OPENCR_STATE" ]] || die "Complete bootstrap on this TurtleBot before exporting."
BOOTSTRAP_VERSION=
OPENCR_REF=
OPENCR_SHA256=
source "$OPENCR_STATE"
[[ "$BOOTSTRAP_VERSION" == "$CONFIGURED_BOOTSTRAP_VERSION" ]] || die "Run bootstrap for v$CONFIGURED_BOOTSTRAP_VERSION before exporting."
[[ "$OPENCR_REF" =~ ^[0-9a-f]{40}$ && "$OPENCR_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Invalid OpenCR bootstrap record."

export_packages() {
  local name="$1" spec package installed version
  shift
  printf '%s=(\n' "$name"
  for spec in "$@"; do
    package="${spec%%=*}"
    installed="$(dpkg-query -W -f='${db:Status-Status}\t${Version}' "$package")" || die "Package not installed: $package"
    [[ "$installed" == installed$'\t'* ]] || die "Package not installed: $package"
    version="${installed#*$'\t'}"
    [[ -n "$version" ]] || die "Missing version: $package"
    printf '  %q\n' "$package=$version"
  done
  printf ')\n\n'
}

OUTPUT_FILE="$(mktemp "$SNAPSHOT_FILE.XXXXXX")"
trap 'rm -f -- "$OUTPUT_FILE"' EXIT
{
  printf '# exported bootstrap snapshot; preserve this version record\n'
  printf 'BOOTSTRAP_VERSION=%q\n' "$BOOTSTRAP_VERSION"
  printf 'TARGET_CODENAME=%q\nTARGET_ARCH=%q\n\n' "$TARGET_CODENAME" "$TARGET_ARCH"
  export_packages PREREQUISITE_PACKAGES "${PREREQUISITE_PACKAGES[@]}"
  export_packages DOCKER_PACKAGES "${DOCKER_PACKAGES[@]}"
  printf 'OPENCR_REF=%q\nOPENCR_SHA256=%q\n' "$OPENCR_REF" "$OPENCR_SHA256"
} > "$OUTPUT_FILE"
chmod 0644 "$OUTPUT_FILE"
ln "$OUTPUT_FILE" "$SNAPSHOT_FILE"
printf 'Exported installed versions to %s\n' "$SNAPSHOT_FILE"
