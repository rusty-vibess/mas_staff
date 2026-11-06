.DEFAULT_GOAL := help

COLOUR_RESET  := \033[0m
COLOUR_YELLOW := \033[33m
COLOUR_CYAN   := \033[36m
DISPLAY_GOALS := $(if $(MAKECMDGOALS),$(MAKECMDGOALS),help)
export MODULE

.PHONY: mast-head help pkg

mast-head:
	@printf "$(COLOUR_CYAN)==>$(COLOUR_RESET) MAS Staff packages\n"
	@printf "$(COLOUR_CYAN)==>$(COLOUR_RESET) Command: $(COLOUR_YELLOW)$(DISPLAY_GOALS)$(COLOUR_RESET)\n"

help: mast-head ## Show available commands.
	@printf "\nUsage: $(COLOUR_YELLOW)make pkg MODULE=turtlebot3$(COLOUR_RESET)\n"

pkg: mast-head ## Export a versioned package archive.
	@bash scripts/pkg_export.sh
