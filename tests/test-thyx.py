import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
loader = importlib.machinery.SourceFileLoader("thyx_sync", str(ROOT / "system/usr/local/lib/thyx-sync-background"))
spec = importlib.util.spec_from_loader(loader.name, loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)


class ThyxSyncTest(unittest.TestCase):
    def test_wallpaper_changes_update_the_public_copy_and_palette(self):
        with tempfile.TemporaryDirectory() as temporary:
            home = Path(temporary) / "home"
            current = home / ".local/state/omarchy/current"
            current.mkdir(parents=True)
            config = home / ".config/thyx"
            config.mkdir(parents=True)
            (config / "settings.json").write_text('{"title":"Xmilon"}')
            Image.new("RGB", (20, 20), "white").save(config / "solo.png")
            first, second = home / "one.png", home / "two.png"
            Image.new("RGB", (40, 20), "#123860").save(first)
            Image.new("RGB", (40, 20), "#604812").save(second)
            link = current / "background"
            link.symlink_to(first)
            output = Path(temporary) / "public"
            sync.sync(home, output)
            before = (output / "background.jpg").read_bytes()
            palette = (output / "theme.conf.user").read_text()
            link.unlink()
            link.symlink_to(second)
            sync.sync(home, output)
            self.assertNotEqual(before, (output / "background.jpg").read_bytes())
            self.assertNotEqual(palette, (output / "theme.conf.user").read_text())
            self.assertIn('DisplayName="Xmilon"', palette)
            self.assertEqual((output / "avatar.png").stat().st_mode & 0o777, 0o644)
            with Image.open(output / "avatar.png") as avatar:
                self.assertEqual(avatar.size, (256, 256))

    def test_missing_wallpaper_preserves_previous_state(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "public"
            output.mkdir()
            target = output / "background.jpg"
            target.write_bytes(b"previous")
            with self.assertRaises(FileNotFoundError):
                sync.sync(Path(temporary) / "no-home", output)
            self.assertEqual(target.read_bytes(), b"previous")


if __name__ == "__main__":
    unittest.main()
