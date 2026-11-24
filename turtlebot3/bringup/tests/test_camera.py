"""Exercise the onboard GStreamer reader with generated H.264 video."""

from contextlib import closing
import os
import re
import signal
import subprocess
import sys
import time
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from scripts.decode_camera import Decoder
from workspace.services.camera import Gst, PACKET_SINK, is_keyframe, read_packets

SYNTHETIC_VIDEO_TEMPLATE = (
    "video/x-raw,format=I420,width={width},height={height},framerate={fps}/1"
    " ! x264enc tune=zerolatency speed-preset=ultrafast bitrate=500 key-int-max=5"
    " option-string=scenecut=0 ! " + PACKET_SINK
)
SYNTHETIC_VIDEO = SYNTHETIC_VIDEO_TEMPLATE.format(width=640, height=480, fps=5)


class CameraTests(unittest.TestCase):
    def test_annex_b_packets_decode_after_loss(self):
        with closing(read_packets("videotestsrc num-buffers=12 ! " + SYNTHETIC_VIDEO)) as stream:
            packets = [next(stream) for _ in range(12)]
            with self.assertRaisesRegex(RuntimeError, "end of stream"):
                next(stream)

        self.assertEqual([index for index, data in enumerate(packets) if is_keyframe(data)], [0, 5, 10])
        for index in (0, 5, 10):
            nal_types = {match[1][0] & 0x1F for match in re.finditer(rb"\x00\x00\x01(.)", packets[index], re.DOTALL)}
            self.assertTrue({7, 8}.issubset(nal_types))

        def message(index):
            data = packets[index]

            return SimpleNamespace(encoding="h264", pts=index, flags=int(is_keyframe(data)), data=data)

        decoder = Decoder()
        self.assertTrue(decoder.decode(message(0)))
        for index in (2, 3, 4):
            self.assertEqual(decoder.decode(message(index)), [])

        frames = decoder.decode(message(5))
        self.assertEqual(len(frames), 1)
        self.assertEqual((frames[0].width, frames[0].height), (640, 480))
        self.assertTrue(decoder.decode(message(6)))

    def test_pipeline_error(self):
        description = "videotestsrc ! identity error-after=1 ! appsink name=packets"
        with self.assertRaisesRegex(RuntimeError, "Camera pipeline failed"):
            next(read_packets(description, timeout=2))

    def test_capture_timeout_releases_pipeline(self):
        Gst.init(None)
        pipeline = Gst.parse_launch("appsrc is-live=true ! appsink name=packets")
        with patch.object(Gst, "parse_launch", return_value=pipeline):
            with self.assertRaisesRegex(RuntimeError, "Timed out"):
                next(read_packets("", timeout=0.1))

        self.assertEqual(pipeline.get_state(0).state, Gst.State.NULL)

    def test_closing_the_stream_releases_pipeline(self):
        Gst.init(None)
        pipeline = Gst.parse_launch("videotestsrc is-live=true ! " + SYNTHETIC_VIDEO)
        with patch.object(Gst, "parse_launch", return_value=pipeline):
            with closing(read_packets("")) as stream:
                self.assertTrue(is_keyframe(next(stream)))

        self.assertEqual(pipeline.get_state(0).state, Gst.State.NULL)

    def test_publish_to_existing_ros_topic_and_shut_down(self):
        from ffmpeg_image_transport_msgs.msg import FFMPEGPacket
        import rclpy
        from rclpy.qos import QoSProfile, ReliabilityPolicy

        name = f"camera_test_{os.getpid()}"
        decoder = Decoder()
        frames = []
        rclpy.init()
        node = rclpy.create_node(name)

        def receive(message):
            self.assertEqual(message.header.frame_id, f"{name}/camera_optical_frame")
            self.assertEqual(message.encoding, "h264;yuv420p;bgr8;bgr8")
            self.assertEqual((message.width, message.height), (320, 240))
            frames.extend(decoder.decode(message))

        node.create_subscription(
            FFMPEGPacket,
            f"/{name}/camera/video",
            receive,
            QoSProfile(depth=5, reliability=ReliabilityPolicy.BEST_EFFORT),
        )
        command = (
            "from workspace.services import camera\n"
            "import sys\n"
            "camera.CAPTURE_PIPELINE = sys.argv[1]\n"
            "raise SystemExit(camera.main())\n"
        )
        try:
            with subprocess.Popen(
                [sys.executable, "-c", command, "videotestsrc is-live=true ! " + SYNTHETIC_VIDEO_TEMPLATE],
                env=dict(os.environ, ROBOT_NAME=name, CAMERA_RESOLUTION="320x240", CAMERA_FPS="10"),
            ) as publisher:
                try:
                    deadline = time.monotonic() + 10
                    while not frames and publisher.poll() is None and time.monotonic() < deadline:
                        rclpy.spin_once(node, timeout_sec=0.1)

                    self.assertTrue(frames, "No decoded H.264 frame received over ROS")
                    self.assertEqual((frames[0].width, frames[0].height), (320, 240))
                    publisher.send_signal(signal.SIGINT)
                    self.assertEqual(publisher.wait(timeout=5), 0)
                finally:
                    if publisher.poll() is None:
                        publisher.kill()
        finally:
            node.destroy_node()
            rclpy.try_shutdown()


if __name__ == "__main__":
    unittest.main()
