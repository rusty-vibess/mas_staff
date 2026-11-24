#!/usr/bin/env bash

# Compose expands the device settings from .env and the environment.
devices=(
  '${CAMERA_DEVICE:-/dev/video0}'
  '${CAMERA_UNICAM_MEDIA_DEVICE:-/dev/media1}'
  '${CAMERA_ISP_MEDIA_DEVICE:-/dev/media2}'
  /dev/dma_heap
)

# The Pi 4 kernel exposes the sensor, ISP and encoder names through V4L2 sysfs.
for node in /sys/class/video4linux/*; do
  [[ -r "$node/name" ]] && IFS= read -r name < "$node/name" || continue
  case "$name" in
    'imx219 '*|bcm2835-isp-*|bcm2835-codec-encode)
      devices+=("/dev/${node##*/}")
      ;;
  esac
done

device_list=$(printf '"%s",' "${devices[@]}")
printf '{"services":{"tb-ros-humble":{"devices":[%s]},"tb-ros-jazzy":{"devices":[%s]}}}\n' \
  "${device_list%,}" "${device_list%,}"
