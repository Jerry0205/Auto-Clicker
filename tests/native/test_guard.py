"""Guard regression tests: no desktop or real mouse input needed."""

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

from guard import supervise, terminate


class GuardTests(unittest.TestCase):
    def spawn(self, code):
        p = subprocess.Popen([sys.executable, "-c", code])
        self.addCleanup(terminate, p)
        return p

    def test_target_loss_stops_producer(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "events"
            app = self.spawn(
                f'import time\nf=open({str(log)!r}, "w", buffering=1)\n'
                'while True:\n f.write("event\\n"); time.sleep(.01)'
            )
            scenario = self.spawn("import time; time.sleep(20)")
            target = self.spawn("import time; time.sleep(.2)")
            with self.assertRaisesRegex(RuntimeError, "target exited"):
                supervise(app, target, scenario, 2)
            self.assertIsNotNone(app.poll())
            self.assertTrue(log.read_text())
            count = log.stat().st_size
            time.sleep(0.1)
            self.assertEqual(log.stat().st_size, count)

    def test_invisible_target_stops_app(self):
        app = self.spawn("import time; time.sleep(20)")
        target = self.spawn("import time; time.sleep(20)")
        scenario = self.spawn("import time; time.sleep(20)")

        def lost():
            raise RuntimeError("Target disappeared")

        with self.assertRaisesRegex(RuntimeError, "disappeared"):
            supervise(app, target, scenario, 2, lost)
        self.assertIsNotNone(app.poll())
        self.assertIsNone(target.poll())

    def test_scenario_failure_stops_app_before_target(self):
        app = self.spawn("import time; time.sleep(20)")
        target = self.spawn("import time; time.sleep(20)")
        scenario = self.spawn("raise SystemExit(3)")
        self.assertEqual(supervise(app, target, scenario, 2), 3)
        self.assertIsNotNone(app.poll())
        self.assertIsNone(target.poll())


if __name__ == "__main__":
    unittest.main()
