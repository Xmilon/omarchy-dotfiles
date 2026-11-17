"""Exercise the installed QML login lifecycle without contacting Spotify."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PLUGIN = Path.home() / ".config/omarchy/plugins/quickshell.spotify"


@unittest.skipUnless(shutil.which("quickshell") and (PLUGIN / "NativeSession.qml").is_file(),
                     "Install the Spotify plugin and dotfiles overrides first")
class NativeSessionTest(unittest.TestCase):
    def test_free_account_exit_settles_and_explains_premium_requirement(self):
        with tempfile.TemporaryDirectory(prefix="spotify-session-check-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            worker = root / "scripts/native-session.sh"
            worker.write_text('#!/bin/sh\necho \'librespot does not support "free" accounts.\' >&2\nexit 1\n')
            worker.chmod(0o700)
            (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import "%s" as Plugin
ShellRoot {
  Plugin.NativeSession { id: session; pluginDir: "%s"; enabled: true }
  Timer { interval: 500; running: true; onTriggered: {
    if (session.loginBusy || !session.sessionChecked || session.lastError.indexOf("Premium") < 0)
      console.error("NATIVE_EXIT_FAIL", session.lastError)
    else console.log("NATIVE_EXIT_PASS")
    Qt.quit()
  } }
}
''' % (PLUGIN.as_uri(), root))
            result = subprocess.run(["quickshell", "-p", str(root)],
                                    env=dict(os.environ, QT_QPA_PLATFORM="offscreen"),
                                    text=True, capture_output=True, timeout=10)
            log = result.stdout + result.stderr
            self.assertIn("NATIVE_EXIT_PASS", log)
            self.assertNotIn("NATIVE_EXIT_FAIL", log)


if __name__ == "__main__":
    unittest.main()
