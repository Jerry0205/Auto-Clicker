"""Exact monitor identity serialization for the native scenario starter."""

import json
import tomllib
import unittest

from run import monitor_identity


class MonitorIdentityTests(unittest.TestCase):
    def test_qml_json_number_format_for_fractional_and_integral_scales(self):
        screen = {
            "name": "eDP-1",
            "manufacturer": "Müller",
            "model": "Panel",
            "serial": "123",
            "width": 1800,
            "height": 1125,
        }
        prefix = '["eDP-1","Müller","Panel","123",1800,1125,'
        for scale, expected in [(1, "1"), (1.25, "1.25"), (1.5, "1.5"), (2.0, "2")]:
            with self.subTest(scale=scale):
                identity = monitor_identity({**screen, "scale": scale})
                self.assertEqual(identity, prefix + expected + "]")
                # The nested JSON must survive the actual TOML string encoding.
                config = tomllib.loads(
                    "monitor_identity = " + json.dumps(identity, ensure_ascii=False)
                )
                self.assertEqual(config["monitor_identity"], identity)


if __name__ == "__main__":
    unittest.main()
