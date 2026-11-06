"""Shared ROS launch callbacks."""

from launch.actions import Shutdown


def stop_session(event, context):
    if context.is_shutdown:
        return []

    if event.returncode != 0:
        raise RuntimeError(f"{event.process_name} exited with status {event.returncode}")

    return [Shutdown(reason=f"{event.process_name} closed")]
