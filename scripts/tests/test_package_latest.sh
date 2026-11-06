#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
mkdir -p "$work_dir/bin" "$work_dir/download"
awk '/^        run: \|/{found=1; next} found {sub(/^          /, ""); print}' \
  "$root/.github/workflows/package-latest.yml" > "$work_dir/workflow.sh"
cat > "$work_dir/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_LOG"
case "$1 $2" in
  'release list') printf 'turtlebot3-v1.1.0\nturtlebot3-v1.2.0\nturtlebot3-extra-v9.0.0\nother-v3.0.0\n' ;;
  'release download') touch "$RUNNER_TEMP/$RELEASE_TAG.tar.gz" ;;
  'release view') [[ "${MOCK_CREATE:-0}" != 1 ]] ;;
  'api repos/'*) printf 'abc123\n' ;;
esac
EOF
chmod +x "$work_dir/bin/gh"
export PATH="$work_dir/bin:$PATH" TEST_LOG="$work_dir/log"
export RUNNER_TEMP="$work_dir/download" GH_REPO=owner/repo

RELEASE_TAG=turtlebot3-v1.2.0 bash "$work_dir/workflow.sh"
grep -q 'release upload turtlebot3-latest .*turtlebot3-latest.tar.gz --clobber' "$TEST_LOG"
grep -q 'git/refs/tags/turtlebot3-latest' "$TEST_LOG"

: > "$TEST_LOG"
MOCK_CREATE=1 RELEASE_TAG=other-v3.0.0 bash "$work_dir/workflow.sh"
grep -q 'release create other-latest --target abc123' "$TEST_LOG"
grep -q 'release upload other-latest .*other-latest.tar.gz --clobber' "$TEST_LOG"
grep -q 'git/refs/tags/other-latest' "$TEST_LOG"

: > "$TEST_LOG"
RELEASE_TAG=turtlebot3-v1.1.0 bash "$work_dir/workflow.sh"
if grep -q 'release upload\|git/refs/tags/' "$TEST_LOG"; then
  printf 'An older release unexpectedly updated the latest alias\n' >&2
  exit 1
fi
printf 'Package latest release checks passed.\n'
