"""Read the namespace configured for this robot."""

import os
import re


def robot_name():
    name = os.environ["ROBOT_NAME"]
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError("Invalid ROBOT_NAME")

    return name
