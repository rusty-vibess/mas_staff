"""Stop the drive when its command publisher disappears."""

from math import isfinite
import signal
from time import monotonic

import rclpy
from geometry_msgs.msg import TwistStamped
from rclpy.clock import Clock, ClockType
from rclpy.node import Node
from rclpy.signals import SignalHandlerOptions


class CommandGuard(Node):
    def __init__(self):
        super().__init__("cmd_vel_guard")
        self.last_command = float("-inf")
        self.publisher = self.create_publisher(TwistStamped, "cmd_vel_guarded", 1)
        self.subscription = self.create_subscription(TwistStamped, "cmd_vel", self.receive, 1)
        self.timer = self.create_timer(
            0.05, self.check_timeout, clock=Clock(clock_type=ClockType.STEADY_TIME)
        )

    def receive(self, message):
        vectors = (message.twist.linear, message.twist.angular)
        if not all(
            isfinite(value) for vector in vectors for value in (vector.x, vector.y, vector.z)
        ):
            self.last_command = float("-inf")
            self.check_timeout()
            return

        self.last_command = monotonic()
        self.publisher.publish(message)

    def check_timeout(self):
        if monotonic() - self.last_command >= 0.5:
            message = TwistStamped()
            message.header.stamp = self.get_clock().now().to_msg()
            self.publisher.publish(message)


def main():
    # unwind callbacks before shutting down the ros context
    rclpy.init(signal_handler_options=SignalHandlerOptions.NO)
    node = CommandGuard()
    stopping = False

    def interrupt(_signal, _frame):
        nonlocal stopping
        stopping = True

    previous = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}
    try:
        while not stopping and rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.1)
    except (KeyboardInterrupt, rclpy.executors.ExternalShutdownException):
        pass
    finally:
        node.destroy_node()
        rclpy.try_shutdown()
        for sig, handler in previous.items():
            signal.signal(sig, handler)


if __name__ == "__main__":
    main()
