"""Run the exact production supervisor shell against isolated fake power settings.

No root, no real pmset writes, no external services. Paths are replaced only in
the extracted test copy. This verifies fallback behavior, not physical Mac sleep.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Sources" / "FreeMacOn" / "main.swift"
MATCH = re.search(r'let supervisorScript = #"""\n(.*?)\n"""#', SOURCE.read_text(), re.S)
assert MATCH, "Production supervisor script not found"

FAKE_POWER = """#!/bin/sh
set -eu
if [ "$1" = "-g" ]; then
  if [ "$TEST_SCENARIO" = "unknown" ]; then
    printf 'Currently in use:\\n'
  else
    printf 'System-wide power settings:\\n SleepDisabled %s\\nCurrently in use:\\n sleep 10\\n' "$(cat "$TEST_FLAG")"
  fi
elif [ "$*" = "-a disablesleep 0" ]; then
  printf 'write\\n' >> "$TEST_WRITES"
  [ "$TEST_SCENARIO" != "write-failure" ] || exit 9
  printf 0 > "$TEST_FLAG"
else
  exit 3
fi
"""

FAKE_HELPER = """#!/bin/sh
set -eu
[ "$1" = "--watchdog" ] || exit 2
case "$TEST_SCENARIO" in no-lock) exit 7;; esac
mkdir "$TEST_LOCK"
printf '%s:active' "$3" > "$TEST_LOCK/status"
printf 1 > "$TEST_FLAG"
case "$TEST_SCENARIO" in
  normal)
    printf 0 > "$TEST_FLAG"
    rm "$TEST_LOCK/status"
    rmdir "$TEST_LOCK"
    exit 0;;
  foreign)
    printf 'some-other-session:active' > "$TEST_LOCK/status"
    exit 7;;
  already-restored)
    printf 0 > "$TEST_FLAG"
    exit 7;;
  crash)
    kill -KILL $$;;
  *) exit 7;;
esac
"""

class SupervisorFaultTests(unittest.TestCase):
    def scenario(self, mode, wrong_digest=False):
        with tempfile.TemporaryDirectory(prefix="freemacon-test-") as tmp:
            root = Path(tmp)
            lock = root / "lock"
            flag = root / "flag"
            writes = root / "writes"
            fake_pmset = root / "fake-pmset"
            helper = root / "helper with space's name"
            flag.write_text("0")
            fake_pmset.write_text(FAKE_POWER); fake_pmset.chmod(0o700)
            helper.write_text(FAKE_HELPER); helper.chmod(0o700)
            digest = hashlib.sha256(helper.read_bytes()).hexdigest()
            if wrong_digest:
                digest = "0" * 64
            # Only this test copy uses mock system paths and reduced retry waits.
            script = MATCH.group(1).replace(
                "/private/var/run/vip.metaver.freemacon-helper.XXXXXX", str(root / "stage.XXXXXX")
            ).replace(
                "lock=/var/run/vip.metaver.freemacon", "lock=" + str(lock)
            ).replace(
                "/usr/bin/pmset", str(fake_pmset)
            ).replace("/bin/sleep 2\n", "/bin/sleep 0\n")
            env = dict(os.environ, TEST_SCENARIO=mode, TEST_LOCK=str(lock),
                       TEST_FLAG=str(flag), TEST_WRITES=str(writes))
            proc = subprocess.run(
                ["/bin/sh", "-c", script, "supervisor-test", str(helper), digest,
                 "501", "our-session", "30", "1000"],
                env=env, capture_output=True, text=True, timeout=40,
            )
            status = (lock / "status").read_text() if (lock / "status").exists() else None
            return proc.returncode, flag.read_text(), status, (
                writes.read_text().count("write") if writes.exists() else 0
            ), len(list(root.glob("stage.*")))

    def test_normal_exit_does_not_double_write(self):
        self.assertEqual(self.scenario("normal"), (0, "0", None, 0, 0))

    def test_killed_watchdog_is_recovered(self):
        self.assertEqual(self.scenario("crash"), (0, "0", None, 1, 0))

    def test_already_restored_needs_no_write(self):
        self.assertEqual(self.scenario("already-restored"), (0, "0", None, 0, 0))

    def test_foreign_session_is_never_touched(self):
        rc, flag, status, writes, stages = self.scenario("foreign")
        self.assertNotEqual(rc, 0)
        self.assertEqual((flag, status, writes, stages), ("1", "some-other-session:active", 0, 0))

    def test_unknown_readback_preserves_recovery_required(self):
        rc, flag, status, writes, stages = self.scenario("unknown")
        self.assertNotEqual(rc, 0)
        self.assertEqual((flag, status, writes, stages), ("0", "our-session:recoveryRequired", 3, 0))

    def test_failed_write_preserves_recovery_required(self):
        rc, flag, status, writes, stages = self.scenario("write-failure")
        self.assertNotEqual(rc, 0)
        self.assertEqual((flag, status, writes, stages), ("1", "our-session:recoveryRequired", 3, 0))

    def test_tampered_executable_is_not_run(self):
        self.assertEqual(self.scenario("normal", wrong_digest=True), (12, "0", None, 0, 0))

    def test_crash_before_lock_has_no_side_effect(self):
        self.assertEqual(self.scenario("no-lock"), (7, "0", None, 0, 0))

if __name__ == "__main__":
    unittest.main()
