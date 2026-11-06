"""Exercise the real command boundary, including a paused simulation clock."""

import time

import rclpy
from geometry_msgs.msg import TwistStamped
from rclpy.executors import SingleThreadedExecutor
from rclpy.parameter import Parameter

from workspace.services.cmd_vel_guard import CommandGuard


def test_forwarding_and_wall_clock_timeout():
    rclpy.init(args=["--ros-args", "-r", "__ns:=/guard_test"])
    guard = CommandGuard()
    guard.set_parameters([Parameter("use_sim_time", value=True)])
    peer = rclpy.create_node("guard_test")
    executor = SingleThreadedExecutor()
    executor.add_node(guard)
    executor.add_node(peer)
    received = []
    subscription = peer.create_subscription(TwistStamped, "cmd_vel_guarded", received.append, 10)
    publisher = peer.create_publisher(TwistStamped, "cmd_vel", 1)

    def wait(predicate, timeout=3.0):
        deadline = time.monotonic() + timeout
        while not predicate():
            assert time.monotonic() < deadline, "Guard response timed out"
            executor.spin_once(timeout_sec=0.01)

    try:
        wait(lambda: publisher.get_subscription_count() and guard.publisher.get_subscription_count())
        message = TwistStamped()
        message.header.frame_id = "test/base_footprint"
        message.twist.linear.x = 0.1
        message.twist.angular.z = 0.4
        received.clear()
        publisher.publish(message)
        wait(lambda: any(item == message for item in received))
        received.clear()
        started = time.monotonic()
        wait(lambda: any(item.twist.linear.x == item.twist.angular.z == 0.0 for item in received))
        assert time.monotonic() - started < 0.7
        assert guard.get_clock().now().nanoseconds == 0

        for invalid in (float("nan"), float("inf")):
            message.twist.linear.x = 0.1
            received.clear()
            publisher.publish(message)
            wait(lambda: any(item == message for item in received))
            message.twist.linear.x = invalid
            received.clear()
            publisher.publish(message)
            wait(lambda: bool(received), timeout=0.2)
            assert all(item.twist.linear.x == item.twist.angular.z == 0.0 for item in received)
    finally:
        executor.shutdown()
        peer.destroy_node()
        guard.destroy_node()
        rclpy.shutdown()
