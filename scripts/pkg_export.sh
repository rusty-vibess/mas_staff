#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${MODULE:-}" ]]; then
  printf 'Error: set MODULE to a top-level package directory name.\n' >&2
  exit 1
fi

if [[ ! "$MODULE" =~ ^[a-zA-Z0-9_-]+$ || "$MODULE" == scripts || "$MODULE" == tmp || "$MODULE" == docs || ! -d "$MODULE" || -L "$MODULE" ]]; then
  printf "Error: '%s' is not an exportable top-level package directory.\n" "$MODULE" >&2
  exit 1
fi

if [[ ! -f "$MODULE/.env" ]]; then
  printf 'Error: %s/.env is missing; a package must define PACKAGE_VERSION.\n' "$MODULE" >&2
  exit 1
fi
version="$(awk -F= '$1 == "PACKAGE_VERSION" { print $2 }' "$MODULE/.env")"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Error: invalid or missing PACKAGE_VERSION in %s/.env.\n' "$MODULE" >&2
  exit 1
fi

archive="tmp/pkg-exports/$MODULE-v$version.tar.gz"
mkdir -p tmp/pkg-exports
temporary_archive="$(mktemp "tmp/pkg-exports/.$MODULE-v$version.XXXXXX")"
trap 'rm -f -- "$temporary_archive"' EXIT
COPYFILE_DISABLE=1 tar --format=ustar --no-xattrs --no-acls --exclude=.DS_Store --exclude='._*' --exclude=__MACOSX --exclude=__pycache__ --exclude=.pytest_cache --exclude='*.pyc' -czf "$temporary_archive" "$MODULE"

if ! tar -xOzf "$temporary_archive" -- "$MODULE/.env" | awk '
  /^[[:space:]]*(export[[:space:]]+)?REMOTE_FILE_EXCHANGE_API_KEY[[:space:]]*=/ {
    sub(/^[^=]*=/, "")
    sub(/[[:space:]]+#.*$/, "")
    gsub(/^[[:space:]]+|[[:space:]]+$/, "")
    if ($0 != "" && $0 != "\"\"" && $0 != "\047\047") exit 1
  }
'; then
  printf 'Error: the package must contain %s/.env with REMOTE_FILE_EXCHANGE_API_KEY blank.\n' "$MODULE" >&2
  exit 1
fi

mv -- "$temporary_archive" "$archive"
printf '\033[36m==>\033[0m Exported %s\n' "$archive"
