import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


class ClipboardSecurityTests(unittest.TestCase):
    def load_helper(self):
        path = Path(__file__).resolve().parents[1] / "bin" / "omafile-helper"
        spec = importlib.util.spec_from_loader("clipboard_security", importlib.machinery.SourceFileLoader("clipboard_security", str(path)))
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        return helper

    def test_clipboard_uses_trusted_lookup_and_environment(self):
        helper = self.load_helper()
        with patch.object(helper, "trusted_program", return_value="/usr/bin/wl-paste") as lookup, \
                patch.object(helper, "trusted_env", return_value={"PATH": "/usr/bin:/bin"}), \
                patch.object(helper.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = b"image/png"
            self.assertEqual(helper.wl_paste(["--list-types"]), b"image/png")
            lookup.assert_called_once_with("wl-paste")
            self.assertEqual(run.call_args.args[0], ["/usr/bin/wl-paste", "--list-types"])
            self.assertEqual(run.call_args.kwargs["env"], {"PATH": "/usr/bin:/bin"})

    def test_untrusted_clipboard_program_is_not_started(self):
        helper = self.load_helper()
        with patch.object(helper, "trusted_program", side_effect=FileNotFoundError), \
                patch.object(helper.subprocess, "run") as run:
            self.assertIsNone(helper.wl_paste(["--list-types"]))
            run.assert_not_called()
