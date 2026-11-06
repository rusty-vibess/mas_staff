# MAS Staff

Staff tooling for the UCL Real-World Multi-Agent Systems labs. The repository contains separately versioned packages for preparing and running the lab hardware.

## Packages

| Package | Purpose |
| --- | --- |
| [`turtlebot3/`](turtlebot3/) | TurtleBot3 host setup, OpenCR firmware, and containerised ROS 2 bringup. |

## Repository structure

```text
mas_staff/
├── README.md
├── docs/
│   ├── bootstrapping.md     # Prepare a new TurtleBot
│   └── bringup.md          # Run and check the robot
└── turtlebot3/
    ├── README.md           # Package overview and commands
    ├── .env                # Robot-specific configuration
    ├── Makefile            # Package commands
    ├── bootstrap/          # Host setup, firmware and version checks
    └── bringup/            # Docker, ROS launch and support services
```

## Getting a package

**Use a tagged [GitHub Release](https://github.com/rusty-vibess/mas_staff/releases) for lab deployment, not a clone of `main`.** Download the versioned `.tar.gz` asset for the package you need (for example, TurtleBot), extract it onto the target device, and follow its own README.

This gives every robot a known package version and avoids deploying whatever happens to be under development.

To create a package archive locally, run `make pkg MODULE=turtlebot3` from the repository root. `MODULE` names a top-level package directory whose `.env` defines `PACKAGE_VERSION`. The archive is written to `tmp/pkg-exports/`. For TurtleBot commands, enter the extracted `turtlebot3/` directory and run `make` to see the available targets.

## Documentation

- [TurtleBot package overview](turtlebot3/README.md) — structure, configuration and commands.
- [Bootstrapping](docs/bootstrapping.md) — preparing a TurtleBot from a fresh SD card.
- [Bringup](docs/bringup.md) — starting, checking and stopping a robot.
