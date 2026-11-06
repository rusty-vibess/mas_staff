#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

source "$(dirname -- "${BASH_SOURCE[0]}")/config.sh" pinned
source /etc/os-release
[[ "${VERSION_CODENAME:-}" == "$TARGET_CODENAME" ]] || die "Expected OS release: $TARGET_CODENAME"
[[ "$(dpkg --print-architecture)" == "$TARGET_ARCH" ]] || die "Expected architecture: $TARGET_ARCH"

for spec in "${PREREQUISITE_PACKAGES[@]}" "${DOCKER_PACKAGES[@]}"; do
  package="${spec%%=*}"
  installed="$(dpkg-query -W -f='${db:Status-Status}\t${Version}' "$package")" || die "Package not installed: $package"
  [[ "$installed" == installed$'\t'* ]] || die "Package not installed: $package"
  version="${installed#*$'\t'}"
  [[ "$version" == "${spec#*=}" ]] || die "$package: expected ${spec#*=}, found $version"
  printf 'OK %s\n' "$spec"
done

EXPECTED_REF="$OPENCR_REF"
EXPECTED_SHA256="$OPENCR_SHA256"
OPENCR_STATE=/var/lib/turtlebot3/opencr-flash.conf
[[ -f "$OPENCR_STATE" ]] || die "Missing OpenCR bootstrap record; run make bootstrap."
BOOTSTRAP_VERSION=
OPENCR_REF=
OPENCR_SHA256=
source "$OPENCR_STATE"
[[ "$BOOTSTRAP_VERSION" == "$CONFIGURED_BOOTSTRAP_VERSION" ]] || die "OpenCR record belongs to a different bootstrap version."
[[ "$OPENCR_REF" == "$EXPECTED_REF" && "$OPENCR_SHA256" == "$EXPECTED_SHA256" ]] || die "OpenCR bootstrap record differs from the manifest."
printf 'OK OpenCR flash record\n'

docker --version
docker compose version
docker buildx version
printf 'Bootstrap v%s smoke check passed.\n' "$BOOTSTRAP_VERSION"
