import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


class BookmarkErrorTests(unittest.TestCase):
    def load_helper(self):
        path = Path(__file__).resolve().parents[1] / "bin" / "omafile-helper"
        spec = importlib.util.spec_from_loader("bookmark_errors", importlib.machinery.SourceFileLoader("bookmark_errors", str(path)))
        helper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(helper)
        return helper

    def test_read_permission_error_is_reported_without_empty_snapshot(self):
        helper = self.load_helper()
        with patch.object(helper, "open", side_effect=PermissionError(13, "Permission denied"), create=True), \
                patch.object(helper.os, "makedirs"), patch.object(helper, "emit") as emit:
            helper.dispatch({"id": 1, "op": "bookmarks"})
            messages = [call.args[0] for call in emit.call_args_list]
            self.assertEqual([message["t"] for message in messages], ["error"])
            self.assertEqual(messages[0]["code"], "EACCES")

    def test_write_does_not_replace_file_when_existing_bookmarks_cannot_be_read(self):
        helper = self.load_helper()
        with patch.object(helper, "read_bookmark_lines", side_effect=PermissionError(13, "Permission denied")), \
                patch.object(helper.os, "replace") as replace, patch.object(helper, "emit") as emit:
            helper.dispatch({"id": 1, "op": "setbookmarks", "items": [{"path": "/saved"}]})
            replace.assert_not_called()
            self.assertEqual(emit.call_args.args[0]["t"], "error")

    def test_missing_bookmarks_file_is_an_empty_first_run(self):
        helper = self.load_helper()
        with tempfile.TemporaryDirectory() as tmp, \
                patch.object(helper, "gtk_bookmarks_file", return_value=str(Path(tmp) / "bookmarks")):
            self.assertEqual(helper.read_bookmark_lines(), [])
