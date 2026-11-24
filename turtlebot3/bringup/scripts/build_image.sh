#!/usr/bin/env bash
set -Eeuo pipefail

service="${1:-}"
case "$service" in
  tb-ros-jazzy|tb-ros-humble) image="turtlebot-tb-${service#tb-ros-}:latest" ;;
  *) printf 'Choose DISTRO=jazzy or DISTRO=humble.\n' >&2; exit 1 ;;
esac
source ./.env

is_pi_image() {
  local platform
  platform="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$1" 2>/dev/null)" &&
    [[ "$platform" == linux/arm64 ]]
}

export_image() (
  if ! is_pi_image "$image"; then
    printf 'Expected a local linux/arm64 image for %s.\n' "$image" >&2
    exit 1
  fi
  output_dir=../tmp/image-exports
  mkdir -p -- "$output_dir"
  temporary_archive="$(mktemp "$output_dir/.$archive.XXXXXX")"
  trap 'rm -f -- "$temporary_archive"' EXIT
  docker image tag "$image" "$exchange_image"
  docker image save "$exchange_image" | gzip > "$temporary_archive"
  mv -- "$temporary_archive" "$output_dir/$archive"
  printf 'Exported %s\n' "$output_dir/$archive"
)

fetch_image() (
  if [[ ! "$REMOTE_FILE_EXCHANGE_FILE_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    printf 'Set a valid REMOTE_FILE_EXCHANGE_FILE_ID in %s.\n' "$bringup_config" >&2
    return 1
  fi

  if is_pi_image "$exchange_image" && docker image tag "$exchange_image" "$image"; then
    printf 'Using local image %s\n' "$exchange_image"
    return 0
  fi

  key="${REMOTE_FILE_EXCHANGE_API_KEY:-}"
  if [[ -z "$key" || "$key" == *$'\r'* || "$key" == *$'\n'* ]]; then
    printf 'Set a valid REMOTE_FILE_EXCHANGE_API_KEY in .env to download images.\n' >&2
    return 1
  fi

  work_dir="$(mktemp -d /tmp/turtlebot-image.XXXXXX)" || return 1
  trap 'rm -rf -- "$work_dir"' EXIT
  curl_progress=(--silent)
  if [[ -t 2 ]]; then curl_progress=(--progress-bar); fi
  if status="$(printf 'apikey: %s\n' "$key" | curl --disable --proto '=https' --globoff \
    "${curl_progress[@]}" --fail --connect-timeout 10 --speed-limit 1024 --speed-time 30 \
    --header @- --output "$work_dir/$archive" --write-out '%{http_code}' \
    --url "${REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI%/}/$REMOTE_FILE_EXCHANGE_FILE_ID")" && [[ "$status" == 200 ]]; then
    printf '\033[36m==>\033[0m Found remote image...\n'
    if docker image load --platform linux/arm64 --input "$work_dir/$archive" &&
      is_pi_image "$exchange_image" && docker image tag "$exchange_image" "$image"; then
      return 0
    fi
    printf 'Downloaded archive did not load the expected image %s.\n' "$exchange_image" >&2
    return 1
  fi

  case "$status" in
    401|403) printf 'File exchange authentication failed (HTTP %s). Check the API key in .env.\n' "$status" >&2 ;;
    404) printf 'Image archive is missing from the file exchange.\n' ;;
    *) printf 'Image download failed (HTTP %s).\n' "${status:-000}" >&2 ;;
  esac
  return 1
)

version_pattern='^[0-9]+\.[0-9]+\.[0-9]+$'
if [[ "${PACKAGE_VERSION:-}" =~ $version_pattern ]]; then
  exchange_image="${image%:*}:${PACKAGE_VERSION}-linux-arm64"
  archive="${image%:*}-v${PACKAGE_VERSION}-linux-arm64.tar.gz"
  if [[ "${2:-}" == --export ]]; then
    export_image
    exit
  fi

  REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI=
  REMOTE_FILE_EXCHANGE_FILE_ID=
  bringup_config="bringup/etc/bringup-v${BRINGUP_VERSION:-}.conf"
  if [[ "${BRINGUP_VERSION:-}" =~ $version_pattern && -f "$bringup_config" ]]; then
    source "$bringup_config" "${service#tb-ros-}"
  fi
  if [[ -n "$REMOTE_FILE_EXCHANGE_DOWNLOAD_API_URI" && -n "$REMOTE_FILE_EXCHANGE_FILE_ID" ]]; then
    if fetch_image; then exit 0; fi
    printf 'Building %s locally.\n' "$service"
  fi
elif [[ "${2:-}" == --export ]]; then
  printf 'Set a valid PACKAGE_VERSION in .env to export images.\n' >&2
  exit 1
fi

docker compose --env-file .env -f bringup/docker-compose.yaml build "$service"
# avoid image bloat by pruning via container LABEL
docker image prune --force --filter 'label=uk.ac.ucl.mas-staff.package=turtlebot3'
