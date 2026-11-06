"""Check the configured robot namespace without ROS or hardware."""

import os
import unittest
from unittest.mock import patch

from workspace.robot_config import robot_name


class RobotNameTest(unittest.TestCase):
    def test_full_namespace_is_preserved(self):
        with patch.dict(os.environ, {"ROBOT_NAME": "tb_111"}):
            self.assertEqual(robot_name(), "tb_111")

    def test_invalid_names_fail(self):
        for name in ("", "1bot", "/tb_111", "tb-111", "tb/111"):
            with self.subTest(name=name), patch.dict(os.environ, {"ROBOT_NAME": name}):
                with self.assertRaises(ValueError):
                    robot_name()

    def test_missing_name_fails(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(KeyError):
                robot_name()


if __name__ == "__main__":
    unittest.main()
