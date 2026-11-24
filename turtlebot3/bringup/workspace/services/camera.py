"""Publish the Pi camera's H.264 stream as ROS packets."""

from contextlib import closing
import os
import re
import signal
import time

import gi

from workspace.robot_config import robot_name

gi.require_version("Gst", "1.0")
from gi.repository import GLib, Gst

PACKET_SINK = (
    "h264parse config-interval=-1 ! video/x-h264,stream-format=byte-stream,alignment=au"
    " ! appsink name=packets sync=false max-buffers=5"
)
CAPTURE_PIPELINE = (
    "libcamerasrc ! video/x-raw,format=NV12,width={width},height={height},framerate={fps}/1,"
    "colorimetry=bt709,interlace-mode=progressive"
    ' ! v4l2h264enc extra-controls="controls,video_bitrate=500000,h264_i_frame_period={fps}"'
    " ! video/x-h264,profile=baseline,level=(string)3.1 ! " + PACKET_SINK
)


def capture_mode():
    try:
        width, height = map(int, os.environ.get("CAMERA_RESOLUTION", "640x480").split("x"))
        fps = int(os.environ.get("CAMERA_FPS", "5"))
    except ValueError as error:
        raise ValueError("Set CAMERA_RESOLUTION to WIDTHxHEIGHT and CAMERA_FPS to an integer") from error

    if min(width, height) <= 0 or width % 2 or height % 2:
        raise ValueError("CAMERA_RESOLUTION needs positive, even dimensions for NV12")
    if fps <= 0:
        raise ValueError("CAMERA_FPS must be positive")

    macroblocks = ((width + 15) // 16) * ((height + 15) // 16)
    if macroblocks > 3600 or macroblocks * fps > 108000:
        raise ValueError("CAMERA_RESOLUTION and CAMERA_FPS exceed H.264 level 3.1")
    return width, height, fps


def is_keyframe(data):
    return any(
        (match[1][0] & 0x1F) == 5 for match in re.finditer(rb"\x00\x00\x01(.)", data, re.DOTALL)
    )


def read_packets(description, timeout=5.0):
    Gst.init(None)
    pipeline = Gst.parse_launch(description)
    try:
        bus = pipeline.get_bus()
        sink = pipeline.get_by_name("packets")
        pipeline.set_state(Gst.State.PLAYING)
        deadline = time.monotonic() + timeout
        while True:
            message = bus.pop_filtered(Gst.MessageType.ERROR | Gst.MessageType.EOS)
            if message is not None:
                if message.type == Gst.MessageType.ERROR:
                    error, debug = message.parse_error()
                    raise RuntimeError(f"Camera pipeline failed: {error.message} ({debug})")

                raise RuntimeError("Camera pipeline reached end of stream")

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError("Timed out waiting for an H.264 packet")

            sample = sink.emit("try-pull-sample", int(min(remaining, 0.1) * Gst.SECOND))
            if sample is not None:
                buffer = sample.get_buffer()
                data = buffer.extract_dup(0, buffer.get_size())
                del buffer, sample
                deadline = time.monotonic() + timeout
                yield data
    finally:
        pipeline.set_state(Gst.State.NULL)


def main():
    from ffmpeg_image_transport_msgs.msg import FFMPEGPacket
    import rclpy
    from rclpy.qos import QoSProfile, ReliabilityPolicy
    from rclpy.signals import SignalHandlerOptions

    name = robot_name()
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    rclpy.init(signal_handler_options=SignalHandlerOptions.NO)
    node = rclpy.create_node("camera", namespace=f"/{name}")
    publisher = node.create_publisher(
        FFMPEGPacket,
        "camera/video",
        QoSProfile(depth=5, reliability=ReliabilityPolicy.BEST_EFFORT),
    )
    try:
        width, height, fps = capture_mode()
        pipeline = CAPTURE_PIPELINE.format(width=width, height=height, fps=fps)
        with closing(read_packets(pipeline)) as packets:
            for sequence, data in enumerate(packets):
                message = FFMPEGPacket(
                    width=width,
                    height=height,
                    encoding="h264;yuv420p;bgr8;bgr8",
                    pts=sequence,
                    flags=int(is_keyframe(data)),
                    data=data,
                )
                message.header.stamp = node.get_clock().now().to_msg()
                message.header.frame_id = f"{name}/camera_optical_frame"
                publisher.publish(message)
    except KeyboardInterrupt:
        pass
    except (GLib.Error, RuntimeError, ValueError) as error:
        node.get_logger().error(str(error))

        return 1
    finally:
        node.destroy_node()
        rclpy.try_shutdown()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
