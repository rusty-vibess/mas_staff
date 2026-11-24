#!/usr/bin/env bash
set -Eeuo pipefail

script="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/pkg_export.sh"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
cd "$work_dir"
mkdir -p example/nested scripts tmp docs
printf 'PACKAGE_VERSION=1.2.3\n' > example/.env
touch example/._metadata
ln -s example linked

MODULE=example bash "$script" > /dev/null
[[ -f tmp/pkg-exports/example-v1.2.3.tar.gz ]]
python3 - <<'PY'
import tarfile

with tarfile.open('tmp/pkg-exports/example-v1.2.3.tar.gz') as archive:
    for member in archive:
        assert not any(part.startswith('._') for part in member.name.split('/'))
        assert not member.pax_headers
PY

printf 'export REMOTE_FILE_EXCHANGE_API_KEY="" # optional\n' >> example/.env
MODULE=example bash "$script" > /dev/null
cp tmp/pkg-exports/example-v1.2.3.tar.gz saved.tar.gz
for version in 1.2.3 1.2.4; do
  printf 'PACKAGE_VERSION=%s\nexport REMOTE_FILE_EXCHANGE_API_KEY="mock-secret-value"\n' "$version" > example/.env
  if MODULE=example bash "$script" > export.log 2>&1; then
    printf 'Export unexpectedly accepted a populated API key\n' >&2
    exit 1
  fi
  grep -Fq 'REMOTE_FILE_EXCHANGE_API_KEY blank' export.log
  if grep -Fq 'mock-secret-value' export.log; then
    printf 'Export leaked the API key in its output\n' >&2
    exit 1
  fi
done
cmp -s saved.tar.gz tmp/pkg-exports/example-v1.2.3.tar.gz
[[ ! -e tmp/pkg-exports/example-v1.2.4.tar.gz ]]

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
