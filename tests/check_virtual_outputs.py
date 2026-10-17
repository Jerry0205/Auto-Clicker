"""Reject a virtual Wayland run whose requested monitor setup was not applied."""

import argparse
import json
import math
import sys
from pathlib import Path


POSITIONS = [(1920, 1080), (3840, 1080), (0, 0)]


def verify_outputs(config, scales):
    outputs = config.get("outputs") if isinstance(config, dict) else None
    names = [f"Virtual-{index}" for index in range(3)]
    if (
        not isinstance(outputs, list)
        or len(outputs) != 3
        or any(not isinstance(output, dict) for output in outputs)
        or any(not isinstance(output.get("name"), str) for output in outputs)
        or sorted(output.get("name", "") for output in outputs) != names
    ):
        raise ValueError("expected exactly Virtual-0, Virtual-1 and Virtual-2")

    by_name = {output["name"]: output for output in outputs}
    for name, position, scale in zip(names, POSITIONS, scales, strict=True):
        output = by_name[name]
        if output.get("enabled") is not True or output.get("connected") is not True:
            raise ValueError(f"{name} must be enabled and connected")
        expected_position = dict(zip(("x", "y"), position))
        if output.get("pos") != expected_position:
            raise ValueError(f"{name}: expected position {expected_position}, got {output.get('pos')}")
        actual_scale = output.get("scale")
        if type(actual_scale) not in (int, float) or not math.isclose(actual_scale, scale, abs_tol=1e-6):
            raise ValueError(f"{name}: expected scale {scale:g}, got {actual_scale}")
    return by_name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("scales", nargs=3, type=float)
    args = parser.parse_args()
    if any(not math.isfinite(scale) or scale <= 0 for scale in args.scales):
        parser.error("scales must be finite positive numbers")
    try:
        outputs = verify_outputs(json.loads(args.config.read_text()), args.scales)
    except (OSError, ValueError) as error:
        print(f"Invalid virtual monitor configuration: {error}", file=sys.stderr)
        return 1
    for name, output in sorted(outputs.items()):
        pos = output["pos"]
        print(f"Verified {name}: enabled, connected, position {pos['x']},{pos['y']}, scale {output['scale']:g}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
