#!/usr/bin/env bash
set -Eeuo pipefail

package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
cat > "$work_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "$*" == *' build '* && "${FAIL_BUILD:-}" == 1 ]]; then exit 1; fi
EOF
chmod +x "$work_dir/docker"
export PATH="$work_dir:$PATH" DOCKER_LOG="$work_dir/docker.log"
cd "$package_dir"

bash bringup/scripts/build_image.sh tb-ros-jazzy
[[ "$(sed -n '1p' "$DOCKER_LOG")" == 'compose --env-file .env -f bringup/docker-compose.yaml build tb-ros-jazzy' ]]
[[ "$(sed -n '2p' "$DOCKER_LOG")" == 'image prune --force --filter label=uk.ac.ucl.mas-staff.package=turtlebot3' ]]
[[ "$(wc -l < "$DOCKER_LOG" | tr -d ' ')" == 2 ]]

: > "$DOCKER_LOG"
if FAIL_BUILD=1 bash bringup/scripts/build_image.sh tb-ros-humble; then
  printf 'Failed build unexpectedly succeeded\n' >&2
  exit 1
fi
[[ "$(wc -l < "$DOCKER_LOG" | tr -d ' ')" == 1 ]]
printf 'Image build and cleanup checks passed.\n'
