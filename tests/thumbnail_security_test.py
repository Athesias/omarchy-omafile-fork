import importlib.machinery
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest
from unittest.mock import patch


def load_helper():
    path = Path(__file__).resolve().parents[1] / "bin" / "omafile-helper"
    spec = importlib.util.spec_from_loader("thumbnail_security", importlib.machinery.SourceFileLoader("thumbnail_security", str(path)))
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    return helper


class ThumbnailSecurityTests(unittest.TestCase):
    def test_user_and_xdg_definitions_are_not_discovered(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "thumbnailers"
            folder.mkdir()
            (folder / "evil.thumbnailer").write_text("[Thumbnailer Entry]\nExec=echo %i\nMimeType=application/x-evil;\n")
            with patch.dict(os.environ, {"XDG_DATA_HOME": tmp, "XDG_DATA_DIRS": tmp}):
                self.assertNotIn("application/x-evil", helper.thumb_tables()["commands"])
            self.assertIsNone(helper.parse_thumbnailer(str(folder / "evil.thumbnailer")))

    def test_absolute_program_must_match_trusted_lookup(self):
        helper = load_helper()
        with patch.object(helper, "trusted_program", return_value="/usr/bin/decoder") as lookup:
            self.assertEqual(helper.thumbnail_program("decoder"), "/usr/bin/decoder")
            self.assertEqual(helper.thumbnail_program("/usr/bin/decoder"), "/usr/bin/decoder")
            with self.assertRaises(FileNotFoundError):
                helper.thumbnail_program("/tmp/decoder")
            lookup.assert_called_with("decoder")

    def test_definition_rejects_untrusted_exec_and_tryexec(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            definition = Path(tmp) / "decoder.thumbnailer"
            for command, try_exec in (("/tmp/decoder %i", ""), ("echo %i", "/tmp/decoder")):
                definition.write_text("[Thumbnailer Entry]\nExec=" + command + "\nTryExec=" + try_exec + "\nMimeType=video/mp4;\n")
                with patch.object(helper, "trusted_thumbnailer", return_value=True):
                    self.assertIsNone(helper.parse_thumbnailer(str(definition)))

    def test_launch_uses_trusted_program_and_environment(self):
        helper = load_helper()
        with patch.object(helper, "trusted_program", return_value="/usr/bin/decoder") as lookup, \
                patch.object(helper, "trusted_env", return_value={"PATH": "/usr/bin:/bin"}), \
                patch.object(helper.subprocess, "Popen") as launch, \
                patch.object(helper.os, "setpriority"):
            launch.return_value.wait.return_value = 0
            self.assertEqual(helper.run_thumbnailer(["decoder", "file;touch marker"], threading.Event()), "ok")
            lookup.assert_called_once_with("decoder")
            self.assertEqual(launch.call_args.args[0], ["/usr/bin/decoder", "file;touch marker"])
            self.assertEqual(launch.call_args.kwargs["env"], {"PATH": "/usr/bin:/bin"})

    def test_symlink_definition_is_rejected(self):
        helper = load_helper()
        with tempfile.TemporaryDirectory() as tmp:
            definition = Path(tmp) / "decoder.thumbnailer"
            definition.symlink_to("/etc/passwd")
            self.assertFalse(helper.trusted_thumbnailer(str(definition)))
