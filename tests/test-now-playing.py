"""The lock screen and the idle still screen share one NowPlaying.qml."""
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LOCK = REPO / "system/usr/share/omarchy/shell/plugins/lock/NowPlaying.qml"
STILL = REPO / "home/.config/xmilon/idle-still/NowPlaying.qml"


class NowPlayingCopies(unittest.TestCase):
    def test_copies_identical(self):
        self.assertEqual(LOCK.read_text(), STILL.read_text())

    def test_display_only(self):
        text = LOCK.read_text()
        for call in ("togglePlaying", ".next()", ".previous()", "execDetached"):
            self.assertNotIn(call, text)


if __name__ == "__main__":
    unittest.main()
