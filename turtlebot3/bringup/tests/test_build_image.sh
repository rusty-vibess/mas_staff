#!/usr/bin/env bash
set -Eeuo pipefail

package_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT
fixture="$work_dir/turtlebot3"
mkdir -p "$fixture/bringup/scripts" "$fixture/bringup/etc" "$fixture/make"
cp "$package_dir/Makefile" "$fixture/"
cp "$package_dir/make/hardware.mk" "$fixture/make/"
cp "$package_dir/bringup/scripts/build_image.sh" "$fixture/bringup/scripts/"
printf 'PACKAGE_VERSION=1.2.3\nBRINGUP_VERSION=1.1.0\nREMOTE_FILE_EXCHANGE_API_KEY=test-key\n' > "$fixture/.env"
printf 'REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=https://exchange.example/api/files/download\nREMOTE_FILE_EXCHANGE_FILE_ID=other-release\n' > "$fixture/bringup/etc/bringup-v1.2.3.conf"
cat > "$work_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_LOG"
if [[ "$*" == *' build '* && "${FAIL_BUILD:-}" == 1 ]]; then exit 1; fi
case "$1 $2" in
  'image inspect')
    [[ "${@: -1}" == *:latest || -f "$LOADED_IMAGE" ]] || exit 1
    printf 'linux/arm64\n'
    ;;
  'image load')
    [[ -s "${@: -1}" ]] || exit 1
    : > "$LOADED_IMAGE"
    ;;
  'image save') printf 'mock image archive\n' ;;
esac
EOF
cat > "$work_dir/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
IFS= read -r header
[[ "$header" == 'apikey: test-key' ]]
printf '%s\n' "${@: -1}" >> "$CURL_LOG"
printf '%s' "$HTTP_STATUS"
[[ "$HTTP_STATUS" == 200 ]] || exit 22
while [[ "$1" != --output ]]; do shift; done
printf 'mock downloaded archive\n' > "$2"
EOF
chmod +x "$work_dir/docker" "$work_dir/curl"
export PATH="$work_dir:$PATH" DOCKER_LOG="$work_dir/docker.log" CURL_LOG="$work_dir/curl.log"
export LOADED_IMAGE="$work_dir/loaded"
cd "$fixture"

REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=https://exchange.example/api/files/download REMOTE_FILE_EXCHANGE_FILE_ID=wrong-release \
  bash bringup/scripts/build_image.sh tb-ros-jazzy
[[ "$(sed -n '1p' "$DOCKER_LOG")" == 'compose --env-file .env -f bringup/docker-compose.yaml build tb-ros-jazzy' ]]
[[ "$(sed -n '2p' "$DOCKER_LOG")" == 'image prune --force --filter label=uk.ac.ucl.mas-staff.package=turtlebot3' ]]
[[ "$(wc -l < "$DOCKER_LOG" | tr -d ' ')" == 2 ]]

: > "$DOCKER_LOG"
bringup_config=bringup/etc/bringup-v1.1.0.conf
printf 'REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=https://exchange.example/api/files/download\nREMOTE_FILE_EXCHANGE_FILE_ID=\n' > "$bringup_config"
if FAIL_BUILD=1 bash bringup/scripts/build_image.sh tb-ros-humble; then
  printf 'Failed build unexpectedly succeeded\n' >&2
  exit 1
fi
[[ "$(wc -l < "$DOCKER_LOG" | tr -d ' ')" == 1 ]]

cat > "$bringup_config" <<'EOF'
REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=https://exchange.example/api/files/download/
case "$1" in
  jazzy) REMOTE_FILE_EXCHANGE_FILE_ID=jazzy_file-id ;;
  humble) REMOTE_FILE_EXCHANGE_FILE_ID=humble_file-id ;;
esac
EOF
for status in 404 401 403; do
  : > "$DOCKER_LOG"
  HTTP_STATUS="$status" bash bringup/scripts/build_image.sh tb-ros-jazzy > "$work_dir/fallback.log" 2>&1
  grep -Fq 'build tb-ros-jazzy' "$DOCKER_LOG"
  if [[ "$status" != 404 ]]; then
    grep -Fq "authentication failed (HTTP $status)" "$work_dir/fallback.log"
  fi
done

: > "$DOCKER_LOG"
: > "$CURL_LOG"
HTTP_STATUS=200 bash bringup/scripts/build_image.sh tb-ros-jazzy
bash bringup/scripts/build_image.sh tb-ros-jazzy
printf 'REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=https://exchange.example/api/files/download\n' >> "$bringup_config"
LOADED_IMAGE="$work_dir/humble-loaded" HTTP_STATUS=200 bash bringup/scripts/build_image.sh tb-ros-humble
[[ "$(< "$CURL_LOG")" == $'https://exchange.example/api/files/download/jazzy_file-id\nhttps://exchange.example/api/files/download/humble_file-id' ]]
grep -Fq 'image load --platform linux/arm64 --input /tmp/' "$DOCKER_LOG"
grep -Fxq 'image tag turtlebot-tb-jazzy:1.2.3-linux-arm64 turtlebot-tb-jazzy:latest' "$DOCKER_LOG"
grep -Fxq 'image tag turtlebot-tb-humble:1.2.3-linux-arm64 turtlebot-tb-humble:latest' "$DOCKER_LOG"
if grep -Fq ' build ' "$DOCKER_LOG"; then exit 1; fi

if make export-image DISTRO= > "$work_dir/export.log" 2>&1; then
  printf 'Export unexpectedly accepted a missing DISTRO\n' >&2
  exit 1
fi
grep -Fq 'Choose DISTRO=jazzy or DISTRO=humble.' "$work_dir/export.log"
for distro in jazzy humble; do
  make export-image DISTRO="$distro"
  gzip -t "../tmp/image-exports/turtlebot-tb-$distro-v1.2.3-linux-arm64.tar.gz"
  grep -Fxq "image save turtlebot-tb-$distro:1.2.3-linux-arm64" "$DOCKER_LOG"
done
printf 'Image build, download and export checks passed.\n'
