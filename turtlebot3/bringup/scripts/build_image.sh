#!/usr/bin/env bash
set -Eeuo pipefail

docker compose --env-file .env -f bringup/docker-compose.yaml build "$1"
# avoid image bloat by pruning via container LABEL
docker image prune --force --filter 'label=uk.ac.ucl.mas-staff.package=turtlebot3'
