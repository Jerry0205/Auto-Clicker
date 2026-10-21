"""Regression checks for silent KScreen setup failures; no desktop required."""

import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_virtual_outputs import verify_outputs


class VirtualOutputTests(unittest.TestCase):
    def configured(self, scales=(1, 1.5, 2)):
        return {"outputs": [
            {"name": "Virtual-2", "enabled": True, "connected": True, "pos": {"x": 0, "y": 0}, "scale": scales[2]},
            {"name": "Virtual-0", "enabled": True, "connected": True, "pos": {"x": 1920, "y": 1080}, "scale": scales[0]},
            {"name": "Virtual-1", "enabled": True, "connected": True, "pos": {"x": 3840, "y": 1080}, "scale": scales[1]},
        ]}

    def test_accepts_effective_three_monitor_scenarios_in_any_output_order(self):
        for scales in [(1, 1, 1), (1.5, 1.5, 1.5), (1, 1.5, 2)]:
            with self.subTest(scales=scales):
                self.assertEqual(len(verify_outputs(self.configured(scales), scales)), 3)

    def test_rejected_layout_cannot_report_a_successful_test_setup(self):
        # Actual state after KWin rejects the old negative-position request.
        config = self.configured((1, 1, 1))
        for output in config["outputs"]:
            index = int(output["name"][-1])
            output["pos"] = {"x": index * 1920, "y": 0}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "outputs.json"
            path.write_text(json.dumps(config))
            result = subprocess.run(
                [sys.executable, str(Path(__file__).resolve().parents[1] / "check_virtual_outputs.py"), str(path), "1", "1", "1"],
                capture_output=True, text=True,
            )
        self.assertEqual(result.returncode, 1)
        self.assertIn("expected position", result.stderr)
        self.assertNotIn("Verified", result.stdout)

    def test_rejects_ignored_fractional_scale(self):
        with self.assertRaisesRegex(ValueError, "expected scale 1.5"):
            verify_outputs(self.configured((1, 1, 1)), (1, 1.5, 2))

    def test_rejects_missing_extra_disabled_and_disconnected_outputs(self):
        valid = self.configured()
        missing = copy.deepcopy(valid)
        missing["outputs"].pop()
        extra = copy.deepcopy(valid)
        extra["outputs"].append({"name": "Virtual-3", "enabled": False})
        duplicate = copy.deepcopy(valid)
        duplicate["outputs"][0]["name"] = "Virtual-0"
        disabled = copy.deepcopy(valid)
        disabled["outputs"][0]["enabled"] = False
        disconnected = copy.deepcopy(valid)
        disconnected["outputs"][0]["connected"] = False
        for config in [missing, extra, duplicate, disabled, disconnected]:
            with self.subTest(config=config), self.assertRaises(ValueError):
                verify_outputs(config, (1, 1.5, 2))


if __name__ == "__main__":
    unittest.main()
