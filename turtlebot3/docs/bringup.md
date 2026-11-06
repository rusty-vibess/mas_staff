# TurtleBot3 Bringup

This is the normal procedure for starting a TurtleBot at the beginning of a lab. It assumes the Raspberry Pi has already been prepared using [Bootstrapping](bootstrapping.md). Bringup runs the robot drivers in a container; it does not install Docker or reflash OpenCR.

The **TurtleBot** is the robot and its onboard Raspberry Pi; the **remote** is the separate computer used to connect to and control it.

## 1. Check the robot configuration

Connect to the Pi over SSH and enter the extracted TurtleBot package:

```bash
cd turtlebot3
```

Check `.env` before starting the drivers. The current package defaults are:

```bash
# Package versions
PACKAGE_VERSION=1.1.0
BOOTSTRAP_VERSION=1.0.1
BRINGUP_VERSION=1.0.0

# ROS 2: Runtime config
ROS_DOMAIN_ID=30
ROBOT_NAME=tb_NO_NAME

# TurtleBot: Hardware and device config
LDS_MODEL=LDS-02
LDS_DEVICE=/dev/ttyUSB0
OPENCR_PORT=/dev/ttyACM0
OPENCR_MODEL=burger

# Extra: Provides crash protection; if /cmd_vel recieves no update for 0.5s, set vel to 0.0
CMD_VEL_GUARD=true
# Extra: Provides UDP port manager; resolves unusual packet routes (e.g. Linux VM -> Host OS -> TB)
MANAGED_GATEWAY=false
```

The important relationships are:

- **`BRINGUP_VERSION`** identifies the bringup version; it does not select a configuration.
- **`ROS_DOMAIN_ID`** must match the controllers ROS 2 domain. Robots meant to communicate in the same ROS graph should use the same domain.
- **`ROBOT_NAME`** is the *full* robot namespace, defaulting to `tb_NO_NAME`. Give each robot a unique name. Use letters, digits and underscores, with a letter/underscore first; do not include a leading `/`.
- **`OPENCR_MODEL` / `OPENCR_PORT`** must agree with the physical platform and USB serial device.
- **`LDS_MODEL` / `LDS_DEVICE`** select the LiDAR model and USB serial device.
- **`CMD_VEL_GUARD`** enables a command-loss safety stop. We recommend leaving it enabled.
- **`MANAGED_GATEWAY`** enables the route-registration service used by compatible Docker Desktop remotes. It is not required for remotes with direct network reachability.

The Make commands supply `.env` to Docker Compose, which passes the relevant settings into the ROS container. You can set the same keys in the terminal environment to override Compose's file values, but keeping each robot's identity in `.env` is less error-prone.

## 2. Start the robot

From the `turtlebot3/` package directory, run **one** of:

```bash
make tb-jazzy      # ROS 2 Jazzy
# or
make tb-humble     # ROS 2 Humble
```

The selected command builds the Docker image if needed and launches the onboard TurtleBot3 drivers. The first build may take longer because it downloads and installs ROS packages. Subsequent runs reuse the built image.

After a successful build, bringup removes unused, untagged images labelled as belonging to this TurtleBot package. Images in use and images from other projects are left alone. Images built before this labelling was added are not included.

Both configurations:

- Use host networking so ROS traffic can reach the local network.
- Map the configured OpenCR and LiDAR devices into the container.
- Run the TurtleBot nodes in `/${ROBOT_NAME}` and set `use_sim_time=false`.
- Optionally start the `cmd_vel` guard and route-registration service.

Use the ROS distribution that matches your remote setup. This matters particularly for velocity commands: **Jazzy expects `geometry_msgs/msg/TwistStamped`; Humble expects `geometry_msgs/msg/Twist`.**

Leave this terminal running during the lab. To stop bringup, press **Ctrl-C**; the container is stopped and removed, but the built image remains available for next time.

To open a shell in the matching robot container, use `make shell-jazzy` for Jazzy or `make shell-humble` for Humble. If the service is already running, the command opens a shell in that container. Otherwise, it builds the image if needed and starts a temporary container with a shell; this does not start the drivers. Exit the shell with `exit`.

### How Docker is configured

A Docker **image** contains the software needed to run the drivers; a **container** is a running instance of that image. The Make command builds the selected image and starts its container.

[`bringup/docker-compose.yaml`](../bringup/docker-compose.yaml) defines the Humble and Jazzy services and their shared runtime settings, including networking, devices and environment variables. It takes the relevant values from `.env`, so change that file for normal robot configuration.

The [Jazzy Dockerfile](../bringup/docker/Dockerfile.tb) and [Humble Dockerfile](../bringup/docker/Dockerfile.tb-humble) define the software installed in each image and the launch command it runs. To add software to an image, update the appropriate Dockerfile; update both if both distributions need it. The bringup workspace is mounted into the container read-only by Compose.

## 3. Check ROS from the remote

On the **remote**, source its ROS 2 environment and select the same domain as the robot. For a Jazzy remote, for example:

```bash
source /opt/ros/jazzy/setup.bash
export ROS_DOMAIN_ID=30

ros2 node list
ros2 topic list
```

Replace `30` with the configured domain. If the remote uses its own Docker environment, run these commands *inside that environment* instead.

Look for topics beneath the robot namespace, such as `/tb_NO_NAME/scan`. Once found, check that LiDAR messages are arriving:

```bash
ros2 topic hz /tb_NO_NAME/scan
```

Substitute your `ROBOT_NAME` if it differs. You can inspect the velocity-command interface before driving:

```bash
ros2 topic info /tb_NO_NAME/cmd_vel -v
```

Do not start moving the robot until its LiDAR, odometry and control topics are visible and the space around it is clear.

## 4. Optional services

### Command guard

With `CMD_VEL_GUARD=true`, the guard forwards finite commands from `cmd_vel` to the driver's `cmd_vel_guarded` topic. It sends zero velocity for invalid commands or after **0.5 seconds** without a valid command, using monotonic time even if the ROS clock stalls. Publish commands continuously, with gaps comfortably below 0.5 seconds.

The guard does not limit speed or acceleration. With `CMD_VEL_GUARD=false`, the driver receives `cmd_vel` directly; only disable it when another suitable safety arrangement is in place.

### Managed gateway

`MANAGED_GATEWAY=true` enables temporary return routes to compatible Docker Desktop VMs on the remote. A remote-side client, supplied separately, must announce its subnet over UDP **45888** and renew its 10-second lease. The robot validates requests and removes routes when leases expire or are released.

Use this service on a **trusted lab LAN**; it is not an authenticated gateway. Leave it disabled when the remote is directly reachable.

## 5. Troubleshooting

| Symptom | What to check |
| --- | --- |
| `make tb-*` fails before ROS starts | Docker access after login, available disk space and the container build output. |
| OpenCR or LiDAR device cannot open | USB connections, `OPENCR_PORT` and `LDS_DEVICE`; check available `/dev/ttyACM*` and `/dev/ttyUSB*` devices. |
| Remote sees no robot topics | Both sides' `ROS_DOMAIN_ID`, robot namespace, remote ROS environment and network/DDS reachability. |
| Topics exist but LiDAR is absent | LiDAR power, USB device mapping, `LDS_MODEL`, and the container logs. |
| Robot receives commands but stops almost immediately | Check that commands arrive continuously (under 0.5-second gaps) with finite values and the correct Twist/TwistStamped type. |
| Docker Desktop remote has one-way connectivity | Confirm the remote-side route client is running, UDP 45888 is reachable, domains match and a route lease is being renewed. |
| Bringup exits after a child process closes | Inspect the ROS/Docker terminal output; the launch session deliberately shuts down when one of its child processes exits. |
| Dependency checks fail | Run `make check` and compare with the configured snapshot. Do not switch to unpinned installation just to suppress a mismatch. |

For a one-time host or firmware problem, return to [Bootstrapping](bootstrapping.md). For normal operation, **leave bringup running, verify ROS on the remote, then start the lab workload**.
