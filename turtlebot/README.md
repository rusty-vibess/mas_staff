# From 0 to Working TurtleBot Instructions

Last updated: 5th Nov 2026

## Step 1 — SD Setup:
Flash the SD card for the bot. Ensure to use a 32GB micro-SD to avoid memory constraints causing TurtleBot related issues.

At time of writing, the lab uses Raspberry Pi 4 boards. Ensure to select the appropriate board.

Use the official [Raspberry Pi Imager](https://www.raspberrypi.com/software/).

We opt to flash the Pi OS Lite as it is lighter than installing a full Ubuntu OS or a full Pi OS image. Pi OS Lite is under `Raspberry Pi OS (other)` at time of writing.

Ensure to set the wifi SSID and password correctly and ensure to allow ssh with password enabled (this is the OS user password, not related to the network password).

The Pi imager is pretty straightforward just follow it.

We prefer user: ubuntu, password: ubuntu for all TurtleBots for simplicity.

## Step 2 — Docker/ROS 2:
To avoid complex teardown and system bloat we keep the OS as light as possible.

Opting instead to configure ROS inside a Docker container. This means we keep the OS strictly to basic tooling and Docker, all our ROS work exists inside a docker container that can be easily ripped apart and rebuilt.

The [setup script](bootstrap/scripts/setup_opencr_docker.sh) installs Docker and host tooling, and flashes OpenCR firmware. It expects Raspberry Pi OS Lite Trixie 64-bit (arm64); run as your normal user, without `sudo`. From this directory on the TurtleBot:

```bash
make             # show available commands
make bootstrap
# or run directly without Make
bash bootstrap/scripts/setup_opencr_docker.sh
```

The defaults are `BOOTSTRAP_VERSION=1.0.0`, `OPENCR_MODEL=burger` and `OPENCR_PORT=/dev/ttyACM0`. Change these in the optional [.env](.env), or override them from the terminal, for example `OPENCR_MODEL=waffle make bootstrap`. Exported variables and inline overrides take precedence over `.env`. The script also works directly without Make or `.env`, using its hardcoded settings defaults; keep the `bootstrap/` directory together.

`BOOTSTRAP_VERSION` is independent of the overall TurtleBot package version. Bootstrap files live under `bootstrap/`; the README, `.env` and Make commands stay at the package root. The target is Trixie/arm64, independent of the SD image's release date.

By default, setup requires `bootstrap/etc/bootstrapped-versions-v<BOOTSTRAP_VERSION>.conf` and validates its stamp. Missing snapshots fail before installation. Packages are installed with the exact exported versions; unavailable versions fail through APT without falling back to an unpinned install. The v1.0.0 snapshot contains the versions exported from the first configured TurtleBot.

To resolve a fresh baseline, pass `--not-pinned`. This ignores any versioned snapshot and uses [the initial dependency definitions](bootstrap/etc/bootstrap-versions.conf):

```bash
make bootstrap BOOTSTRAP_ARGS=--not-pinned
# or run directly
bash bootstrap/scripts/setup_opencr_docker.sh --not-pinned
```

After checking that the installation works, run `make export` on that TurtleBot. This creates the configured version's snapshot, containing its version stamp, installed package pins and flashed OpenCR commit/checksum. Exports preserve existing snapshots and refuse to overwrite them; choose a new `BOOTSTRAP_VERSION` when capturing another baseline.

Run `make check` on the TurtleBot to compare every listed package against its exported version, check the recorded OpenCR commit/checksum, and smoke test the Docker, Compose and Buildx commands. Unpinned or missing dependencies fail the check. The OpenCR flash record stays on that TurtleBot at `/var/lib/turtlebot/bootstrap-opencr.conf`; the check does not query firmware directly from the board.

For another dependency set, choose a new `BOOTSTRAP_VERSION`, edit the initial package arrays or firmware reference as needed, bootstrap with `--not-pinned` on the TurtleBot, and export again. `make check` always uses the configured snapshot. Keep earlier snapshots with the package as records.

## Step 3 — Robot bringup

On the TurtleBot, run `make tb-humble` or `make tb-jazzy` to build and start the onboard drivers. Press Ctrl-C to stop them. Both commands use the robot model and OpenCR port from `.env`, along with the ROS domain, lidar settings and watchdog option there. The ROS domain must match the station.

Set `ROBOT_NAME` in `.env` to the full robot namespace, such as `tb_111`; it must match the station configuration and be unique on the network. The watchdog stops the robot when commands cease. `MANAGED_GATEWAY=true` enables route registration for a Docker Desktop station.
