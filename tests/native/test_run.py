"""Exact monitor identity serialization for the native scenario starter."""

import tomllib
import unittest

from run import config_text, monitor_identity


class MonitorIdentityTests(unittest.TestCase):
    screen = {
        "name": "eDP-1",
        "manufacturer": "Müller",
        "model": "Panel",
        "serial": "123",
        "width": 1800,
        "height": 1125,
    }

    def test_qml_json_number_format_for_fractional_and_integral_scales(self):
        prefix = '["eDP-1","Müller","Panel","123",1800,1125,'
        cases = [
            (1, "1"),
            (1.0, "1"),
            (1.25, "1.25"),
            (1.5, "1.5"),
            (7 / 6, "1.1666666666666667"),
            (2.0, "2"),
        ]
        for scale, expected in cases:
            with self.subTest(scale=scale):
                screen = {**self.screen, "scale": scale}
                identity = prefix + expected + "]"
                self.assertEqual(monitor_identity(screen), identity)
                # The written config must parse and return the identity unchanged.
                config = tomllib.loads(config_text(screen))
                self.assertEqual(config["monitor_identity"], identity)
                self.assertEqual(config["position_mode"], "fixed")

    def test_toml_escapes_characters_that_qml_json_keeps_raw(self):
        # JSON.stringify keeps DEL and emoji raw; TOML forbids a raw DEL.
        screen = {**self.screen, "name": "eDP\x7f-1", "model": "Panel 🖥", "scale": 1.25}
        identity = '["eDP\x7f-1","Müller","Panel 🖥","123",1800,1125,1.25]'
        self.assertEqual(monitor_identity(screen), identity)
        text = config_text(screen)
        self.assertNotIn("\x7f", text)
        self.assertEqual(tomllib.loads(text)["monitor_identity"], identity)


if __name__ == "__main__":
    unittest.main()
