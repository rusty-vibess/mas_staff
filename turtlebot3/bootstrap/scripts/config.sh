(( $# <= 1 )) || die "Expected at most one option: --not-pinned."
BOOTSTRAP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$(cd -- "$BOOTSTRAP_DIR/.." && pwd)"

# preserve terminal overrides while loading the optional package configuration
OPENCR_PORT_OVERRIDE="${OPENCR_PORT:-}"
OPENCR_MODEL_OVERRIDE="${OPENCR_MODEL:-}"
BOOTSTRAP_VERSION_OVERRIDE="${BOOTSTRAP_VERSION:-}"
if [[ -f "$PACKAGE_DIR/.env" ]]; then
  source "$PACKAGE_DIR/.env"
fi
OPENCR_PORT="${OPENCR_PORT_OVERRIDE:-${OPENCR_PORT:-/dev/ttyACM0}}"
OPENCR_MODEL="${OPENCR_MODEL_OVERRIDE:-${OPENCR_MODEL:-burger}}"
BOOTSTRAP_VERSION="${BOOTSTRAP_VERSION_OVERRIDE:-${BOOTSTRAP_VERSION:-1.0.2}}"
[[ "$BOOTSTRAP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "BOOTSTRAP_VERSION must be MAJOR.MINOR.PATCH."
CONFIGURED_BOOTSTRAP_VERSION="$BOOTSTRAP_VERSION"

VERSIONS_FILE="$BOOTSTRAP_DIR/etc/bootstrap-version.conf"
SNAPSHOT_FILE="$BOOTSTRAP_DIR/etc/bootstrap-v$BOOTSTRAP_VERSION.conf"
case "${1:-pinned}" in
  --not-pinned)
    [[ -f "$VERSIONS_FILE" ]] || die "Missing dependency definitions: $VERSIONS_FILE"
    source "$VERSIONS_FILE"
    BOOTSTRAP_VERSION="$CONFIGURED_BOOTSTRAP_VERSION"
    ;;
  pinned)
    [[ -f "$SNAPSHOT_FILE" ]] || die "Missing bootstrap snapshot: $SNAPSHOT_FILE"
    BOOTSTRAP_VERSION=
    source "$SNAPSHOT_FILE"
    [[ "$BOOTSTRAP_VERSION" == "$CONFIGURED_BOOTSTRAP_VERSION" ]] || die "Snapshot version does not match configured bootstrap version."
    [[ "$OPENCR_REF" =~ ^[0-9a-f]{40}$ && "$OPENCR_SHA256" =~ ^[0-9a-f]{64}$ ]] || die "Snapshot contains unpinned OpenCR firmware."
    ;;
  *) die "Unknown bootstrap option: $1; expected --not-pinned." ;;
esac

package_spec_pattern='^[a-z0-9][a-z0-9+.-]*(:[a-z0-9-]+)?(=[0-9][a-zA-Z0-9.+:~-]*\*?)?$'
for spec in "${PREREQUISITE_PACKAGES[@]}" "${DOCKER_PACKAGES[@]}"; do
  [[ "$spec" =~ $package_spec_pattern ]] || die "Invalid package specification: $spec"
done

installed_package_version() {
  local spec="$1" package installed version
  package="${spec%%=*}"
  installed="$(dpkg-query -W -f='${db:Status-Status}\t${Version}' "$package")" || die "Package not installed: $package"
  [[ "$installed" == installed$'\t'* ]] || die "Package not installed: $package"
  version="${installed#*$'\t'}"
  [[ -n "$version" ]] || die "Missing version: $package"
  if [[ "$spec" == *=* && "$version" != ${spec#*=} ]]; then
    die "$package: expected ${spec#*=}, found $version"
  fi
  printf '%s\n' "$version"
}
