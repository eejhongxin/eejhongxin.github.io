"""Isolated unified-installer checks; never mount or change the real /etc or /mnt."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
INSTALLER = ROOT / "tools/ddr-unified-install.sh"
PREPARE = ROOT / "tools/ddr-unified-boot.sh"
HOOK = "/bin/sh /etc/init.d/ddr_boot_prepare.sh > /tmp/ddr-boot.log 2>&1"


class UnifiedInstallTests(unittest.TestCase):
    shell = ["/bin/sh"]

    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="ddr-unified-install-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.mnt = self.root / "mnt"
        self.work = self.mnt / "ddr_work"
        self.work.mkdir(parents=True)
        self.mem = self.root / "mem"
        self.mem.mkdir()
        self.etc = self.root / "etc/init.d"
        self.etc.mkdir(parents=True)
        self.rc = self.etc / "rcS"
        self.original_rc = (b"#!/bin/sh\r\n# factory startup\r\n"
                            b" \t/sbin/mdev\t-s \t\r\n"
                            b"# original trailing spaces  \r\nexit 0\n")
        self.rc.write_bytes(self.original_rc)
        self.rc.chmod(0o750)
        self.target = self.etc / "ddr_boot_prepare.sh"
        self.original_helper = b"#!/bin/sh\n# existing helper, do not lose\n"
        self.target.write_bytes(self.original_helper)
        self.target.chmod(0o755)
        self.count = self.work / "ddr_autostart.count"
        self.count.write_bytes(b"8\n")
        self.logs = self.work / "ddr_all_test"
        self.logs.mkdir()
        (self.logs / "ddr_log.log").write_bytes(b"existing test data\n")
        self.mounts = self.root / "mounts"
        self.mounted()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.validations = self.root / "validations"
        self.real_stat = shutil.which("stat")
        self.mock("id", 'echo "${FAKE_UID:-0}"\n')
        self.mock("ps", '[ "${ACTIVE:-0}" = 0 ] || echo "123 sh ./ddr_test.sh -c 6"\n')
        self.mock("sync", ":\n")
        self.mock("stat", 'if [ "$1" = -c ] && [ "$2" = %d ]; then\n'
                  '    if [ "${DIFFERENT_DEVICE:-0}" = 1 ] && [ "$3" = "$PACKAGE_UNDER_TEST" ]; then\n'
                  '        echo 43\n'
                  '    else\n'
                  '        echo 42\n'
                  '    fi\n'
                  'else\n'
                  f'    exec "{self.real_stat}" "$@"\n'
                  'fi\n')
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        RUN_CALLS=str(self.calls), VALIDATION_CALLS=str(self.validations),
                        TEST_RUN_LOCK=str(self.mem / "ddr-run.lock"))
        self.package = self.create_package("ddr_p5")

    def mock(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/sh\n" + body)
        path.chmod(0o755)

    def mounted(self, source="/dev/mmcblk1p7", kind="vfat", options="rw,relatime"):
        self.mounts.write_text(f"{source} {self.mnt} {kind} {options} 0 0\n")

    def create_package(self, relative):
        package = self.work / relative
        boot = package / "boot"
        boot.mkdir(parents=True, exist_ok=True)
        for name in ("run.sh", "ddr_test.sh", "ddr_progress.sh", "wtd_feed.sh"):
            (package / name).write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$RUN_CALLS"\n')
        (package / "run.sh").write_text(
            '#!/bin/sh\n'
            'if [ "$*" = --validate-autostart ]; then\n'
            '    [ -f "$TEST_RUN_LOCK/installer.pid" ] || exit 91\n'
            '    printf "%s\\n" "$*" >> "$VALIDATION_CALLS"\n'
            '    exit "${VALIDATION_EXIT:-0}"\n'
            'fi\n'
            'printf "%s\\n" "$*" >> "$RUN_CALLS"\n')
        prepare = PREPARE.read_text().replace("/mnt", str(self.mnt))
        prepare = prepare.replace("/proc/mounts", str(self.mounts))
        (boot / "prepare.sh").write_text(prepare)
        source = INSTALLER.read_text()
        source = source.replace("PATH=/sbin:/bin:/usr/sbin:/usr/bin", 'PATH="$PATH"')
        source = source.replace("/mnt", str(self.mnt)).replace("/mem/", str(self.mem) + "/")
        source = source.replace("/proc/mounts", str(self.mounts))
        source = source.replace("RC=/etc/init.d/rcS", f"RC={self.rc}")
        source = source.replace("TARGET=/etc/init.d/ddr_boot_prepare.sh", f"TARGET={self.target}")
        # Pin mocks because BusyBox ash may prefer a built-in applet to PATH.
        source = source.replace("$(id -u)", f'$("{self.bin}/id" -u)')
        source = source.replace("if ps |", f'if "{self.bin}/ps" |')
        source = source.replace("stat -c ", f'"{self.bin}/stat" -c ')
        source = source.replace("    sync\n", f'    "{self.bin}/sync"\n')
        source = source.replace("\nsync\n", f'\n"{self.bin}/sync"\n')
        (boot / "install.sh").write_text(source)
        return package

    def run_installer(self, *args, **env):
        return subprocess.run(self.shell + [str(self.package / "boot/install.sh"), *args],
                              env=dict(self.env, PACKAGE_UNDER_TEST=str(self.package), **env),
                              text=True, capture_output=True, timeout=8)

    def rootfs_snapshot(self):
        return {str(p.relative_to(self.etc)): (p.read_bytes(), p.stat().st_mode & 0o777)
                for p in self.etc.rglob("*") if p.is_file()}

    def assert_unchanged_after_failure(self, result, before):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.rootfs_snapshot(), before)
        self.assertEqual(self.count.read_bytes(), b"8\n")
        self.assertEqual((self.logs / "ddr_log.log").read_bytes(), b"existing test data\n")
        self.assertFalse(self.calls.exists())
        self.assertFalse((self.work / "ddr_backup").exists())
        self.assertFalse((self.mem / "ddr-unified-install.lock").exists())

    def test_both_package_locations_are_pinned_and_existing_logs_are_untouched(self):
        for relative in ("ddr_p5", "full/ddr_p5"):
            with self.subTest(relative=relative):
                self.package = self.create_package(relative)
                result = self.run_installer("autostart", "6")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                text = self.target.read_text()
                self.assertIn(f"PACKAGE={self.package}\n", text)
                self.assertNotIn("__DDR_PACKAGE__", text)
                self.assertIn('exec sh "$PACKAGE/run.sh" --boot', text)
                self.assertEqual(self.count.read_bytes(), b"6\n")
                self.assertIn("--validate-autostart", self.validations.read_text())
                self.assertFalse(self.calls.exists())
                self.assertEqual((self.logs / "ddr_log.log").read_bytes(), b"existing test data\n")
                self.assertFalse((self.work / "ddr_backup").exists())
                self.assertFalse((self.mem / "ddr-run.lock").exists())

    def test_repeat_install_keeps_one_hook_and_first_backups_exactly(self):
        first = self.run_installer("autostart", "6")
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        anchor = b" \t/sbin/mdev\t-s \t\r\n"
        expected = self.original_rc.replace(anchor, anchor + HOOK.encode() + b"\n")
        self.assertEqual(self.rc.read_bytes(), expected)
        self.assertEqual(self.rc.stat().st_mode & 0o777, 0o750)
        self.assertEqual(Path(str(self.rc) + ".before-ddr-boot").read_bytes(), self.original_rc)
        self.assertEqual(Path(str(self.target) + ".before-unified-ddr").read_bytes(), self.original_helper)
        self.rc.write_bytes(self.rc.read_bytes() + b"# later user change\r\n")
        for _ in range(2):
            result = self.run_installer("autostart", "8")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.rc.read_bytes(), expected + b"# later user change\r\n")
        self.assertEqual(self.rc.read_bytes().count(HOOK.encode()), 1)
        self.assertEqual(Path(str(self.rc) + ".before-ddr-boot").read_bytes(), self.original_rc)
        self.assertEqual(Path(str(self.target) + ".before-unified-ddr").read_bytes(), self.original_helper)
        self.assertEqual(self.count.read_bytes(), b"8\n")

    def test_existing_crlf_hook_is_reused_without_rewriting_rcs(self):
        contents = self.original_rc + HOOK.encode() + b"\r\n"
        self.rc.write_bytes(contents)
        result = self.run_installer("autostart", "6")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.rc.read_bytes(), contents)

    def test_missing_duplicate_and_commented_anchors_reject_without_rootfs_changes(self):
        for contents in (b"#!/bin/sh\nexit 0\n", self.original_rc + b"/sbin/mdev -s\n",
                         b"#!/bin/sh\n# /sbin/mdev -s\n/sbin/mdev -s extra\n"):
            with self.subTest(contents=contents):
                self.rc.write_bytes(contents)
                before = self.rootfs_snapshot()
                self.assert_unchanged_after_failure(self.run_installer("autostart", "6"), before)

    def test_missing_readonly_wrong_mounts_reject_without_rootfs_changes(self):
        before = self.rootfs_snapshot()
        self.mounts.write_text("")
        self.assert_unchanged_after_failure(self.run_installer("autostart", "6"), before)
        for source, kind, options in (("/dev/mmcblk1p7", "vfat", "ro,relatime"),
                                      ("/wrong", "vfat", "rw"),
                                      ("/dev/mmcblk1p7", "tmpfs", "rw")):
            with self.subTest(source=source, kind=kind, options=options):
                self.mounted(source, kind, options)
                self.assert_unchanged_after_failure(self.run_installer("autostart", "6"), before)

    def test_nonroot_active_test_and_foreign_package_device_are_rejected(self):
        before = self.rootfs_snapshot()
        for env in ({"FAKE_UID": "1000"}, {"ACTIVE": "1"}, {"DIFFERENT_DEVICE": "1"}):
            with self.subTest(env=env):
                self.assert_unchanged_after_failure(self.run_installer("autostart", "6", **env), before)

    def test_running_or_stale_run_lock_is_not_removed_or_overwritten(self):
        lock = self.mem / "ddr-run.lock"
        lock.mkdir()
        (lock / "pid").write_bytes(b"777\n")
        before = self.rootfs_snapshot()
        self.assert_unchanged_after_failure(self.run_installer("autostart", "6"), before)
        self.assertEqual((lock / "pid").read_bytes(), b"777\n")
        self.assertEqual(sorted(p.name for p in lock.iterdir()), ["pid"])

    def test_validation_failure_rejects_before_any_rootfs_backup_or_write(self):
        before = self.rootfs_snapshot()
        result = self.run_installer("autostart", "6", VALIDATION_EXIT="17")
        self.assert_unchanged_after_failure(result, before)
        self.assertEqual(self.validations.read_text(), "--validate-autostart\n")
        self.assertIn("failed validation", result.stderr)
        self.assertFalse((self.mem / "ddr-run.lock").exists())

    def test_manual_disables_future_tests_while_current_worker_and_helper_stay(self):
        lock = self.mem / "ddr-run.lock"
        lock.mkdir()
        (lock / "pid").write_bytes(b"777\n")
        before = self.rootfs_snapshot()
        result = self.run_installer("manual", ACTIVE="1")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.count.exists())
        self.assertEqual(self.rootfs_snapshot(), before)
        self.assertEqual((lock / "pid").read_bytes(), b"777\n")
        self.assertEqual((self.logs / "ddr_log.log").read_bytes(), b"existing test data\n")
        self.assertFalse(self.calls.exists())

    def test_bad_template_and_bad_rounds_do_not_partially_install(self):
        before = self.rootfs_snapshot()
        for rounds in ("0", "06", "1001", "-1", "text"):
            with self.subTest(rounds=rounds):
                self.assert_unchanged_after_failure(self.run_installer("autostart", rounds), before)
        (self.package / "boot/prepare.sh").write_text("if\n")
        self.assert_unchanged_after_failure(self.run_installer("autostart", "6"), before)
        self.assertFalse((self.mem / "ddr-run.lock").exists())


@unittest.skipUnless(shutil.which("busybox"), "BusyBox is unavailable")
class BusyboxUnifiedInstallTests(UnifiedInstallTests):
    shell = [shutil.which("busybox"), "sh"]


if __name__ == "__main__":
    unittest.main()
