COMPOSE := docker compose --env-file .env -f bringup/docker-compose.yaml

# prefer Make and terminal overrides over values read from Compose
hardware-setting = $(if $(filter undefined,$(origin $(1))),\
	$(patsubst $(1)=%,%,$(filter $(1)=%,$(2))),$($(1)))

check-hardware-flag = $(if $(filter-out true false,$(2)),$(error $(1) must be true or false))

# default to OpenCR on and camera off, matching the base Compose file
use-opencr = $(call check-hardware-flag,USE_OPENCR,$(1))$(if $(filter false,$(1)),false,true)
use-camera = $(call check-hardware-flag,USE_CAMERA,$(1))$(if $(filter true,$(1)),true,false)

compose-settings = $(shell $(COMPOSE) config --environment)
hardware-selection = \
	$(if $(filter true,$(call use-opencr,$(call hardware-setting,USE_OPENCR,$(1)))),-f bringup/compose/opencr.yaml) \
	$(if $(filter true,$(call use-camera,$(call hardware-setting,USE_CAMERA,$(1)))),-f <(bash bringup/scripts/camera_devices.sh))

# read Compose settings when a bringup recipe needs them
COMPOSE_WITH_HARDWARE = $(COMPOSE) $(strip $(call hardware-selection,$(compose-settings)))

# Pass the camera device list to Compose while keeping stdin available for interactive shells.
tb-humble tb-jazzy shell-humble shell-jazzy: SHELL := /bin/bash

# report the effective flags used to select the device mappings
.PHONY: use-opencr use-camera

use-opencr:
	@printf '%s\n' '$(call use-opencr,$(call hardware-setting,USE_OPENCR,$(compose-settings)))'

use-camera:
	@printf '%s\n' '$(call use-camera,$(call hardware-setting,USE_CAMERA,$(compose-settings)))'
