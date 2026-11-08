import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("input_ui", ROOT / "tools/check_input_ui.py")
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


class InputSafetyTests(unittest.TestCase):
    def test_lifetime_selector_regression(self):
        self.assertEqual(ui.forbidden_callbacks("@objc func release() {}"), ["release"])
        self.assertEqual(ui.forbidden_callbacks("@objc(release) private func cleanUp() {}"), ["release"])
        for name in ["retain", "autorelease", "retainCount", "dealloc"]:
            self.assertEqual(ui.forbidden_callbacks(f"@objc private func {name}() {{}}"), [name])
        self.assertEqual(ui.forbidden_callbacks("@objc func resetHeldInputs() {}\nstatic func release() {}"), [])

    def test_application_callbacks_are_safe(self):
        ui.audit_callbacks()
