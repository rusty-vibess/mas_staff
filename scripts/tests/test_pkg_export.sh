#!/usr/bin/env bash
set -Eeuo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/pkg_export.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
cd "$work_dir"
mkdir -p example/nested scripts tmp docs
printf 'PACKAGE_VERSION=1.2.3\n' > example/.env
ln -s example linked

MODULE=example bash "$script" > /dev/null
[[ -f tmp/pkg-exports/example-v1.2.3.tar.gz ]]
for module in '' missing scripts tmp docs example/nested ../example linked; do
  if MODULE="$module" bash "$script" > /dev/null 2>&1; then
    printf 'Unexpected export: %s\n' "$module" >&2
    exit 1
  fi
done
printf 'PACKAGE_VERSION=invalid\n' > example/.env
if MODULE=example bash "$script" > /dev/null 2>&1; then
  printf 'Invalid version unexpectedly accepted\n' >&2
  exit 1
fi
printf 'Package export checks passed.\n'
