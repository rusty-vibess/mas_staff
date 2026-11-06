"""Exercise Humble Twist routing and stopping without serial devices."""

import time

import rclpy
from geometry_msgs.msg import Twist
from rclpy.executors import SingleThreadedExecutor
from rclpy.parameter import Parameter

from workspace.services.cmd_vel_guard_humble import CommandGuard
def test_humble_forwarding_validation_and_steady_timeout():
    rclpy.init(args=["--ros-args", "-r", "__ns:=/humble_guard_test"])
    guard = CommandGuard()
    guard.set_parameters([Parameter("use_sim_time", value=True)])
    peer = rclpy.create_node("humble_guard_test")
    executor = SingleThreadedExecutor()
    executor.add_node(guard)
    executor.add_node(peer)
    received = []
    subscription = peer.create_subscription(Twist, "cmd_vel_guarded", received.append, 10)
    publisher = peer.create_publisher(Twist, "cmd_vel", 1)

    def wait(predicate, timeout=3.0):
        deadline = time.monotonic() + timeout
        while not predicate():
            assert time.monotonic() < deadline, "Humble guard response timed out"
            executor.spin_once(timeout_sec=0.01)

    try:
        wait(lambda: publisher.get_subscription_count() and guard.publisher.get_subscription_count())
        message = Twist()
        message.linear.x = 0.1
        message.angular.z = 0.4
        received.clear()
        publisher.publish(message)
        wait(lambda: any(item == message for item in received))
        received.clear()
        started = time.monotonic()
        wait(lambda: any(item == Twist() for item in received))
        assert time.monotonic() - started < 0.7
        assert guard.get_clock().now().nanoseconds == 0

        for vector in ("linear", "angular"):
            for axis in ("x", "y", "z"):
                for invalid in (float("nan"), float("inf"), float("-inf")):
                    message = Twist()
                    message.linear.x = 0.1
                    received.clear()
                    publisher.publish(message)
                    wait(lambda: any(item == message for item in received))
                    setattr(getattr(message, vector), axis, invalid)
                    received.clear()
                    publisher.publish(message)
                    wait(lambda: bool(received), timeout=0.2)
                    assert all(item == Twist() for item in received)
    finally:
        executor.shutdown()
        peer.destroy_node()
        guard.destroy_node()
        rclpy.try_shutdown()
