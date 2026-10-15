"""Version-specific source/package checks; not iOS UI interaction tests."""
from pathlib import Path
import plistlib
import unittest


class SettingsSourceTests(unittest.TestCase):
    def test_settings_compiled(self):
        make = Path("Makefile").read_text()
        self.assertIn("WeChatGroupExtractor_FILES = WGCore.m WGSettings.m", make)

    def test_ui_install_before_filter_gate(self):
        source = Path("WGCore.m").read_text().split("static void WGInstall(void) {", 1)[1]
        self.assertLess(source.index("WGInstallUI();"), source.index("if (gReady || gInstallAttempted) return;"))

    def test_scalar_reverse_supported(self):
        source = Path("WGCore.m").read_text()
        self.assertIn("WGIntegerWidth(reverse.methodReturnType) == 8", source)
        self.assertIn("WGReverseRowSection32", source)
        self.assertIn("WGReversePath", source)

    def test_filter_still_limited(self):
        value = plistlib.loads(Path("WeChatGroupExtractor.plist").read_bytes())
        self.assertEqual(value, {"Filter": {"Bundles": ["com.tencent.xin"]}})

    def test_real_controls_and_handlers(self):
        source = Path("WGSettings.m").read_text()
        for text in ("initWithTitle:@\"分组设置\"", "WGExtractor.Enabled", "WGExtractor.ExcludeSystemUsers",
                     "WGRequestRetry", "UIPasteboard.generalPasteboard.string = WGDiagnostics();"):
            self.assertIn(text, source)
        self.assertNotIn("WCTableViewManager", source)
        self.assertNotIn("UIBlurEffect", source)


if __name__ == "__main__":
    unittest.main()
