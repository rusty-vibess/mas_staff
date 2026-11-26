"""Display a TurtleBot's ROS H.264 stream on the receiving computer."""

import argparse
import re

import av


class Decoder:
    def __init__(self):
        self.codec = None
        self.next_sequence = None

    def decode(self, message):
        if message.encoding.partition(";")[0] != "h264":
            return []
        if message.pts != self.next_sequence:
            self.codec = None
        self.next_sequence = message.pts + 1
        if self.codec is None:
            if not message.flags & 1:
                return []
            self.codec = av.CodecContext.create("h264", "r")
        try:
            return self.codec.decode(av.Packet(bytes(message.data)))
        except av.error.InvalidDataError:
            self.codec = None
            return []


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("robot", help="Robot name, for example tb_111")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", args.robot):
        parser.error("robot must be the robot name without a leading slash")

    import cv2
    from ffmpeg_image_transport_msgs.msg import FFMPEGPacket
    import rclpy
    from rclpy.executors import ExternalShutdownException
    from rclpy.qos import QoSProfile, ReliabilityPolicy

    decoder = Decoder()
    topic = f"/{args.robot}/camera/video_h264"
    title = f"{args.robot} camera"

    def receive(message):
        for frame in decoder.decode(message):
            cv2.imshow(title, frame.to_ndarray(format="bgr24"))

    rclpy.init()
    node = rclpy.create_node("decode_camera")
    node.create_subscription(
        FFMPEGPacket, topic, receive, QoSProfile(depth=5, reliability=ReliabilityPolicy.BEST_EFFORT),
    )
    node.get_logger().info(f"Waiting for video on {topic}")
    try:
        cv2.namedWindow(title, cv2.WINDOW_NORMAL)
        while rclpy.ok():
            rclpy.spin_once(node, timeout_sec=0.1)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
    except (KeyboardInterrupt, ExternalShutdownException):
        pass
    finally:
        cv2.destroyAllWindows()
        node.destroy_node()
        rclpy.try_shutdown()


if __name__ == "__main__":
    main()
