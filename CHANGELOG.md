# Changelog

## `turtlebot3 v1.1.0`

- Renamed the TurtleBot package directory to `turtlebot3/`.
- Added TurtleBot bootstrapping and bringup documentation and updated the README.
- Renamed the `.env` setting `TB_WATCHDOG` to `CMD_VEL_GUARD` and aligned the guard's code and node names.
- Split the Humble and Jazzy Compose services around shared ROS settings; the Make commands remain unchanged.
- Added `make shell-jazzy` and `make shell-humble` to open a shell in a running or temporary robot container.
- Added a root `make pkg` command to export versioned package archives.
- Renamed `TURTLEBOT_VERSION` to `PACKAGE_VERSION` for package exports.
- Added `BRINGUP_VERSION` as an informational version for the bringup component.
- Automatically remove unused, untagged TurtleBot images after a successful build.
- Grouped the command guards and managed gateway under `workspace/services/`.
- Handle managed routes that have already been removed when their leases expire.
- Updated bootstrap to v1.0.1 for the snapshot naming and OpenCR flash record path changes; dependency and firmware pins are unchanged.
