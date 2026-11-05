"""Humble onboard TurtleBot3 drivers with an optional command watchdog."""

from pathlib import Path

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    ExecuteProcess,
    GroupAction,
    IncludeLaunchDescription,
    OpaqueFunction,
    RegisterEventHandler,
)
from launch.event_handlers import OnProcessExit
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import EnvironmentVariable
from launch_ros.actions import SetRemap

from workspace.robot_config import robot_name
from workspace.utils.launch import stop_session


def _launch_robot(context):
    name = robot_name()
    bringup = Path(get_package_share_directory("turtlebot3_bringup"))
    watchdog = IfCondition(EnvironmentVariable("TB_WATCHDOG", default_value="true"))
    return [
        ExecuteProcess(
            cmd=["python3", "-m", "workspace.route_registration"],
            name="route_registration",
            output="screen",
            condition=IfCondition(EnvironmentVariable("MANAGED_GATEWAY", default_value="false")),
        ),
        GroupAction(
            actions=[
                # scope the remap to the driver; the watchdog must keep its original input
                SetRemap(src="cmd_vel", dst="cmd_vel_guarded", condition=watchdog),
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource(str(bringup / "launch/robot.launch.py")),
                    launch_arguments={
                        "namespace": name,
                        "usb_port": EnvironmentVariable("OPENCR_DEVICE"),
                        "use_sim_time": "false",
                    }.items(),
                ),
            ]
        ),
        ExecuteProcess(
            cmd=[
                "python3",
                str(Path(__file__).resolve().parents[2] / "cmd_vel_watchdog_humble.py"),
                "--ros-args",
                "-p",
                "use_sim_time:=false",
                "-r",
                f"__ns:=/{name}",
            ],
            name="cmd_vel_watchdog",
            output="screen",
            condition=watchdog,
        ),
    ]


def generate_launch_description():
    return LaunchDescription(
        [
            RegisterEventHandler(OnProcessExit(on_exit=stop_session)),
            OpaqueFunction(function=_launch_robot),
        ]
    )
