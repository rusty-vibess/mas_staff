# TurtleBot3

The TurtleBot package provides a repeatable way to prepare a Raspberry Pi-based TurtleBot3 and run its ROS 2 drivers. We keep the host OS light: Docker and basic system tooling live on the Pi, while ROS runs inside a disposable container.

The **TurtleBot** is the robot and its onboard Raspberry Pi; the **remote** is the separate computer used to connect to and control it.

It is designed to work as a standalone, versioned package. Download its `.tar.gz` archive from the corresponding [MAS Staff release](https://github.com/rusty-vibess/mas_staff/releases), rather than deploying the latest development tree.

## Package structure

```bash
turtlebot3/
├── .env                       # Per-robot settings
├── Makefile                   # User-facing commands
├── bootstrap/
│   ├── etc/                   # Dependency definitions and version snapshots
│   ├── scripts/               # Installation, export and validation
│   └── tests/
└── bringup/
    ├── docker-compose.yaml    # Containers and device mappings
    ├── docker/                 # Humble and Jazzy images
    ├── workspace/              # Launch files and optional services
    │   └── services/           # Command guards and managed gateway
    └── tests/
```

## Commands

Run these **from the `turtlebot3/` directory on the robot**:

| Command | Purpose |
| --- | --- |
| `make` | Show the available commands. |
| `make bootstrap` | Install host dependencies and flash OpenCR using a pinned bootstrap snapshot. |
| `make check` | Verify installed dependency versions, the OpenCR flash record and Docker tooling. |
| `make tb-jazzy` | Build and run the Jazzy robot drivers. |
| `make tb-humble` | Build and run the Humble robot drivers. |
| `make shell-jazzy` | Open a shell in the Jazzy robot container. |
| `make shell-humble` | Open a shell in the Humble robot container. |
| `make export` | Record a **new** bootstrap baseline after an unpinned setup; not needed for normal bringup. |

For a new robot, bootstrap it once, log out and back in to activate Docker group membership, and run `make check`. For subsequent lab sessions, use the appropriate `make tb-*` command. Press `Ctrl-C` to stop the running container.

> ⚠️ **ROS 2** is installed in the container, so run `ros2` commands from one of these shells on the TurtleBot. Use the relevant `make shell-*` matching your ROS distribution; type `exit` or `ctrl + d` to leave.

## Configuration

The package root `.env` contains the robot settings. Check it before running anything on a new device:

| Setting | Meaning |
| --- | --- |
| `PACKAGE_VERSION` | Package version identifier. |
| `BOOTSTRAP_VERSION` | Independently versioned host dependency/firmware baseline. |
| `BRINGUP_VERSION` | Bringup version identifier; it does not select a configuration. |
| `OPENCR_MODEL`, `OPENCR_PORT` | Burger/Waffle firmware selection and OpenCR serial device. |
| `ROS_DOMAIN_ID` | ROS 2 domain; must agree with the remote. |
| `ROBOT_NAME` | ROS namespace, defaulting to `tb_NO_NAME` (without a leading `/`); give each robot a unique name. |
| `LDS_MODEL`, `LDS_DEVICE` | LiDAR model and serial device. |
| `CMD_VEL_GUARD` | Enable the command-loss safety guard. |
| `MANAGED_GATEWAY` | Enable route registration for remotes using a Docker Desktop VM. |

The bootstrap scripts read `.env` when present, with terminal overrides taking precedence for `BOOTSTRAP_VERSION`, `OPENCR_MODEL` and `OPENCR_PORT`. Docker Compose also uses `.env` for bringup. Configuration lives at the package root, not inside the Docker image.

## What runs on the robot?

The selected ROS 2 container starts the TurtleBot3 drivers in `/${ROBOT_NAME}` using host networking and direct access to the OpenCR and LiDAR devices.

- With `CMD_VEL_GUARD=true`, commands pass through `cmd_vel` → `cmd_vel_guarded` before reaching the driver. Invalid commands or a 0.5-second gap in commands result in a zero-velocity command. This is **not** a speed or acceleration limiter.
- With `MANAGED_GATEWAY=true`, the robot also accepts temporary route registrations from a compatible remote-side client. This is useful when the remote's ROS container lives behind a Docker Desktop VM network.

Jazzy uses `geometry_msgs/msg/TwistStamped` for velocity commands; Humble uses `geometry_msgs/msg/Twist`. The remote's publisher must use the corresponding message type.

## Full instructions

The staff repository maintains the detailed [bootstrapping](https://github.com/rusty-vibess/mas_staff/blob/main/docs/bootstrapping.md) and [bringup](https://github.com/rusty-vibess/mas_staff/blob/main/docs/bringup.md) manuals. When using a tagged package, prefer documentation from the matching release/tag over newer instructions on `main`.
