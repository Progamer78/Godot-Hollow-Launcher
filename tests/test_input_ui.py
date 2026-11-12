import importlib.util
from pathlib import Path
import unittest
import subprocess
from unittest.mock import patch
from contextlib import redirect_stdout
import io
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("input_ui", ROOT / "tools/check_input_ui.py")
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class InputSafetyTests(unittest.TestCase):
    def test_result_requires_success_and_rejects_any_failure(self):
        with tempfile.TemporaryDirectory() as directory, redirect_stdout(io.StringIO()):
            output = Path(directory); source = output / "app-result.log"
            source.write_text("PLAYER_INPUT_UI_PASS: all checks\nPLAYER_INPUT_UI_FAIL: late failure")
            with self.assertRaisesRegex(RuntimeError, "smoke test failed"):
                ui.wait_for_result(source, output, timeout=0)
            self.assertIn("late failure", (output / "run.log").read_text())
            source.write_text("PLAYER_INPUT_UI_CHECK: intermediate PASS")
            with self.assertRaises(RuntimeError): ui.wait_for_result(source, output, timeout=0)
            source.write_text("PLAYER_INPUT_UI_PASS: all checks")
            ui.wait_for_result(source, output, timeout=0)

    def test_missing_completion_fails_and_records_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "no completion record"):
                ui.wait_for_result(output / "absent", output, timeout=0)
            self.assertIn("did not produce", (output / "run.log").read_text())

    def test_lifetime_selector_regression(self):
        self.assertEqual(ui.forbidden_callbacks("@objc func release() {}"), ["release"])
        self.assertEqual(ui.forbidden_callbacks("@objc(release) private func cleanUp() {}"), ["release"])
        for name in ["retain", "autorelease", "retainCount", "dealloc"]:
            self.assertEqual(ui.forbidden_callbacks(f"@objc private func {name}() {{}}"), [name])
        self.assertEqual(ui.forbidden_callbacks("@objc func resetHeldInputs() {}\nstatic func release() {}"), [])

    def test_application_callbacks_are_safe(self):
        ui.audit_callbacks()

    def test_simulator_cleanup_continues_after_shutdown_timeout(self):
        with patch.object(ui.subprocess, "run", side_effect=[subprocess.TimeoutExpired("shutdown", 30), subprocess.CompletedProcess([], 0)]) as run:
            with redirect_stdout(io.StringIO()):
                ui.cleanup_device("test-device")
            self.assertEqual([call.args[0][2] for call in run.call_args_list], ["shutdown", "delete"])
            self.assertTrue(all(call.args[0][-1] == "test-device" for call in run.call_args_list))

    def test_cleanup_cannot_hide_the_test_failure(self):
        with patch.object(ui.subprocess, "run", side_effect=OSError("CoreSimulator unavailable")) as run:
            with redirect_stdout(io.StringIO()):
                with self.assertRaisesRegex(RuntimeError, "original input failure"):
                    try:
                        raise RuntimeError("original input failure")
                    finally:
                        ui.cleanup_device("test-device")
            self.assertEqual(run.call_count, 2)
