# user-facing TurtleBot setup commands
.DEFAULT_GOAL := help

COLOUR_RESET  := \033[0m
COLOUR_YELLOW := \033[33m
COLOUR_CYAN   := \033[36m
DISPLAY_GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),help)

.PHONY: mast-head help bootstrap export check tb-humble tb-jazzy shell-humble shell-jazzy

mast-head:
	@printf "$(COLOUR_CYAN)==>$(COLOUR_RESET) TurtleBot setup\n"
	@printf "$(COLOUR_CYAN)==>$(COLOUR_RESET) Command: $(COLOUR_YELLOW)$(DISPLAY_GOALS)$(COLOUR_RESET)\n"

##@ Main commands
help: mast-head ## Show available commands.
	@printf "\nUsage: $(COLOUR_YELLOW)make <command>$(COLOUR_RESET)\n"
	@printf "Fresh baseline: make bootstrap BOOTSTRAP_ARGS=--not-pinned\n"
	@awk 'BEGIN { FS = ":.*## " } \
		/^##@ / { printf "\n%s\n", substr($$0, 5); next } \
		/^[a-zA-Z0-9_-]+:.*## / { printf "  %-20s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@printf "\n$(COLOUR_CYAN)==>$(COLOUR_RESET) Start here: $(COLOUR_YELLOW)make bootstrap$(COLOUR_RESET)\n"

bootstrap: mast-head ## Install Docker and flash OpenCR.
	@bash bootstrap/scripts/setup_opencr_docker.sh $(BOOTSTRAP_ARGS)

export: mast-head ## Record this bootstrap version.
	@bash bootstrap/scripts/export_versions.sh

check: mast-head ## Check installed dependency versions.
	@bash bootstrap/scripts/check_versions.sh

##@ Robot bringup
tb-humble: mast-head ## Run the Humble robot drivers.
	@bash bringup/scripts/build_image.sh tb-ros-humble
	@docker compose --env-file .env -f bringup/docker-compose.yaml run --rm --pull never --name turtlebot-tb tb-ros-humble

tb-jazzy: mast-head ## Run the Jazzy robot drivers.
	@bash bringup/scripts/build_image.sh tb-ros-jazzy
	@docker compose --env-file .env -f bringup/docker-compose.yaml run --rm --pull never --name turtlebot-tb tb-ros-jazzy

shell-humble: mast-head ## Open a shell in the Humble robot container.
	@container=$$(docker ps -ql --filter status=running --filter label=com.docker.compose.project=turtlebot --filter label=com.docker.compose.service=tb-ros-humble) || exit; \
	if [ -n "$$container" ]; then \
		docker exec -it "$$container" bash; \
	else \
		bash bringup/scripts/build_image.sh tb-ros-humble && \
		docker compose --env-file .env -f bringup/docker-compose.yaml run --rm --pull never tb-ros-humble bash; \
	fi

shell-jazzy: mast-head ## Open a shell in the Jazzy robot container.
	@container=$$(docker ps -ql --filter status=running --filter label=com.docker.compose.project=turtlebot --filter label=com.docker.compose.service=tb-ros-jazzy) || exit; \
	if [ -n "$$container" ]; then \
		docker exec -it "$$container" bash; \
	else \
		bash bringup/scripts/build_image.sh tb-ros-jazzy && \
		docker compose --env-file .env -f bringup/docker-compose.yaml run --rm --pull never tb-ros-jazzy bash; \
	fi
