"""Isolated launcher integration tests; no real mounts, GPIO, or DDR load."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent


class UnifiedTests(unittest.TestCase):
    shell = ['/bin/sh']

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='ddr-unified-test-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.mnt = self.root/'mnt'
        self.work = self.mnt/'ddr_work'
        self.package = self.work/'ddr_p5'
        self.package.mkdir(parents=True)
        self.logs = self.work/'ddr_all_test'
        self.logs.mkdir()
        (self.logs/'old.log').write_text('preserve me\n')
        (self.logs/'runner_exit_code').write_text('0\n')
        self.lock = self.root/'run.lock'
        self.boot_lock = self.root/'boot.lock'
        self.launch = self.root/'launch.log'
        self.calls = self.root/'calls'
        self.bin = self.root/'mock-bin'
        self.bin.mkdir()
        self.mounts = self.root/'mounts'
        self.mounts.write_text(f'/dev/mmcblk1p7 {self.mnt} vfat rw,relatime 0 0\n'+''.join(
            f'/dev/mmcblk1p{n} {p} {fs} ro 0 0\n' for n,p,fs in [
                (5,'/data','ext4'),(1,'/recovery','vfat'),(2,'/firmware','vfat'),
                (3,'/reserve','vfat'),(6,'/data/app/log','ext4')]))
        self.checkupdate = self.root/'checkupdate'
        self.checkupdate.write_text('#!/bin/sh\nexit 0\n')
        self.checkupdate.chmod(0o755)
        self.mock('ps', '[ "${ACTIVE:-0}" = 0 ] || echo "123 sh ./ddr_test.sh -c 6"\n')
        self.mock('id', 'echo 0\n')
        self.mock('sync', ':\n')
        self.mock('dmesg', 'echo "kernel evidence"\n')
        self.mock('usleep', 'sleep 0.03\n')
        self.mock('mount', 'echo "unexpected mount" >> "$CALLS"; exit 1\n')
        for name in ['ddr_progress.sh', 'check_update/check_update_bin/x6_v2.1.2.4B560lcyT_b20201225.bin',
                     'check_update/check_update_tar/update.tar.bz2']:
            p = self.package/name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text('fixture\n')
        (self.package/'wtd_feed.sh').write_text(
            '#!/bin/sh\necho "feeder $1" >> "$CALLS"\n'
            'case "$1" in status) echo "Running: mock feeder"; exit 0 ;; start) exit 9 ;; esac\n')
        (self.package/'ddr_test.sh').write_text(
            '#!/bin/sh\necho "$*" >> "$CALLS"\n'
            'echo "----------count: 0----------" > "$TEST_LOGS/ddr_log.log"\n'
            'echo "[progress] Round 1/$2: stressapptest starting"\n'
            # Reproduce the real runner opening its stderr with tee.
            'echo "SAT output" | tee /proc/self/fd/2\n'
            'sleep "${TEST_DELAY:-0.05}"\n'
            'exit "${RUNNER_EXIT:-0}"\n')
        source = (ROOT/'tools/ddr-run.sh').read_text()
        source = source.replace('WORK=/mnt/ddr_work', f'WORK={self.work}')
        source = source.replace('MOUNTPOINT=/mnt', f'MOUNTPOINT={self.mnt}')
        source = source.replace('MOUNTS=/proc/mounts', f'MOUNTS={self.mounts}')
        source = source.replace('LOCK=/mem/ddr-run.lock', f'LOCK={self.lock}')
        source = source.replace('BOOT_LOCK=/mem/ddr-autotest.lock', f'BOOT_LOCK={self.boot_lock}')
        source = source.replace('LAUNCH_LOG=/tmp/ddr-run-launch.log', f'LAUNCH_LOG={self.launch}')
        source = source.replace('PATH="$PACKAGE/bin:/sbin:/bin:/usr/sbin:/usr/bin"', 'PATH="$MOCK_BIN:/usr/bin:/bin"')
        source = source.replace('/data/sbin/checkupdate', str(self.checkupdate))
        source = source.replace('/tmp/ddr-package-check.log', str(self.root/'package-check.log'))
        source = source.replace('/tmp/check_update_$kind', str(self.root)+'/check_update_$kind')
        # BusyBox may prefer built-in applets; pin mocked commands in both shells.
        for name in ['ps', 'id', 'sync', 'dmesg', 'usleep', 'mount']:
            if name == 'id':
                source = source.replace('$(id -u)', f'$("{self.bin}/id" -u)')
            elif name == 'ps':
                source = source.replace('ps |', f'"{self.bin}/ps" |')
            else:
                import re
                source = re.sub(r'(?m)(?<![\w/"\'-])\b'+name+r' (?=[^\n])', f'"{self.bin/name}" ', source)
                source = source.replace('\n    '+name+'\n', '\n    "'+str(self.bin/name)+'"\n')
        self.entry = self.package/'run.sh'
        self.entry.write_text(source)
        self.manifest()
        self.env = dict(os.environ, MOCK_BIN=str(self.bin), CALLS=str(self.calls),
                        TEST_LOGS=str(self.logs))

    def mock(self, name, body):
        p = self.bin/name
        p.write_text('#!/bin/sh\n'+body)
        p.chmod(0o755)

    def manifest(self):
        paths = sorted(p for p in self.package.rglob('*') if p.is_file() and p.name != 'SHA256SUMS')
        (self.package/'SHA256SUMS').write_text(''.join(
            hashlib.sha256(p.read_bytes()).hexdigest()+'  '+str(p.relative_to(self.package))+'\n' for p in paths))

    def run_entry(self, *args, **env):
        return subprocess.run(self.shell+[str(self.entry)]+list(args),
                              env=dict(self.env, **env), text=True, capture_output=True, timeout=10)

    def finish(self):
        end = time.monotonic()+6
        while self.lock.exists() and time.monotonic()<end:
            time.sleep(0.03)
        self.assertFalse(self.lock.exists(), self.launch.read_text() if self.launch.exists() else '')

    def test_background_run_archives_logs_and_retains_console_header(self):
        r = self.run_entry('6', RUNNER_EXIT='7')
        self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
        self.assertIn('Started: 6 rounds', r.stdout)
        self.finish()
        backups = list((self.work/'ddr_backup').glob('previous.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0]/'ddr_all_test/old.log').read_text(), 'preserve me\n')
        self.assertEqual((self.logs/'runner_exit_code').read_text(), '7\n')
        console = (self.logs/'console.log').read_text()
        self.assertTrue(console.startswith('DDR rounds=6;'))
        self.assertIn('SAT output', console)
        self.assertIn('inspect SAT, memtester', console)
        self.assertIn('-c 6', self.calls.read_text())
        self.assertNotIn('feeder start', self.calls.read_text())

    def test_wrong_readonly_mount_and_missing_fixture_preserve_logs(self):
        original = self.mounts.read_text()
        for text in [original.replace('vfat rw,', 'vfat ro,'), original.replace('/dev/mmcblk1p7', '/wrong')]:
            self.mounts.write_text(text)
            r = self.run_entry('6')
            self.assertNotEqual(r.returncode, 0)
            self.assertTrue((self.logs/'old.log').exists())
            self.assertFalse(self.lock.exists())
        self.mounts.write_text(original)
        (self.package/'check_update/check_update_tar/update.tar.bz2').unlink()
        r = self.run_entry('6')
        self.assertNotEqual(r.returncode, 0)
        self.assertTrue((self.logs/'old.log').exists())
        self.assertFalse(self.lock.exists())

    def test_invalid_rounds_and_existing_test_never_archive(self):
        for value in ['0', '06', '-1', '1001', 'text']:
            self.assertNotEqual(self.run_entry(value).returncode, 0)
        self.assertNotEqual(self.run_entry('6', ACTIVE='1').returncode, 0)
        self.assertTrue((self.logs/'old.log').exists())
        self.assertFalse((self.work/'ddr_backup').exists())

    def test_existing_full_layout_runs_the_called_package(self):
        destination = self.work/'full/ddr_p5'
        destination.parent.mkdir()
        self.package.rename(destination)
        self.package = destination
        self.entry = destination/'run.sh'
        result = self.run_entry('3')
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.finish()
        self.assertIn('package='+str(destination), (self.logs/'console.log').read_text())
        self.assertIn('-c 3', self.calls.read_text())

    def test_run_lock_serializes_startup_but_allows_later_batch(self):
        first = self.run_entry('6', TEST_DELAY='1')
        self.assertEqual(first.returncode, 0, first.stdout+first.stderr)
        self.assertNotEqual(self.run_entry('6').returncode, 0)
        self.finish()
        self.assertEqual(self.run_entry('2').returncode, 0)
        self.finish()
        self.assertEqual(len(list((self.work/'ddr_backup').glob('previous.*'))), 2)

    def test_archive_failure_reports_failure_despite_old_success_code(self):
        (self.work/'ddr_backup').write_text('not a directory\n')
        r = self.run_entry('6')
        self.assertNotEqual(r.returncode, 0, r.stdout+r.stderr)
        self.finish()
        self.assertTrue((self.logs/'old.log').exists())
        self.assertNotIn('-c 6', self.calls.read_text())

    def test_boot_runs_once_and_progress_uses_actual_batch_total(self):
        (self.work/'ddr_autostart.count').write_text('6\n')
        self.assertEqual(self.run_entry('--boot').returncode, 0)
        self.finish()
        self.assertEqual(self.run_entry('--boot').returncode, 0)
        self.assertEqual(self.calls.read_text().count('-c 6'), 1)
        (self.work/'ddr_autostart.count').write_text('8\n')
        result = self.run_entry('progress')
        self.assertIn('Round 1/6', result.stdout)
        self.assertNotIn('Round 1/8', result.stdout)


@unittest.skipUnless(shutil.which('busybox'), 'BusyBox not installed')
class BusyboxUnifiedTests(UnifiedTests):
    shell = [shutil.which('busybox'), 'sh']


if __name__ == '__main__':
    unittest.main()
