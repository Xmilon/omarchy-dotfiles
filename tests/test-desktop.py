import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("updates", str(ROOT / "home/.local/bin/omarchy-app-updates"))
spec = importlib.util.spec_from_loader(loader.name, loader)
updates = importlib.util.module_from_spec(spec)
loader.exec_module(updates)


class UpdatesTest(unittest.TestCase):
    def test_installed_apps_and_new_apps(self):
        rows = updates.package_rows("discord 1.0.169\nt3code-bin 0.1.9\nnew-app 2.0\n")
        self.assertEqual([row["id"] for row in rows], ["pkg:discord", "pkg:t3code-bin", "pkg:new-app"])
        self.assertIn("T3 Code", rows[1]["label"])

    def test_untrusted_names_do_not_become_shell_commands(self):
        self.assertEqual(updates.package_rows("--overwrite 1\nfoo;id 1\n$(id) 1\n"), [])
        with patch.object(updates.shutil, "which", return_value="/usr/bin/yay"):
            command = updates.update_command({"id": "pkg:new-app", "package": "new-app"})
        self.assertEqual(command, ["yay", "-Syu", "--", "new-app"])

    def test_flatpak_target_is_an_argument(self):
        self.assertEqual(updates.update_command({"id": "flatpak:org.example.App", "app": "org.example.App"}),
                         ["flatpak", "update", "--", "org.example.App"])

    def test_unknown_target_is_rejected(self):
        with self.assertRaises(ValueError):
            updates.update_command({"id": "not-installed"})

    def test_menu_labels_are_plain_text(self):
        self.assertEqual(updates.menu_label('<img src="https://example.invalid"> & music'),
                         '&lt;img src="https://example.invalid"&gt; &amp; music')


if __name__ == "__main__":
    unittest.main()
