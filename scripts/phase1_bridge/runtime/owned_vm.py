"""One foreground owner's disposable API36 KVM process; no account operations.

The reviewed workflow prepares a fresh fixed AVD before calling this module.
Private emulator output is never included in evidence or returned in errors.
"""
from __future__ import annotations

from datetime import datetime, timezone
import math
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import time


class VmBlocked(RuntimeError):
    pass


def require(value, code):
    if not value:
        raise VmBlocked(code)


def child_environment(env):
    # Account and action credentials have no purpose in the emulator/adb process.
    allowed = {'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL', 'LC_CTYPE',
               'TZ', 'TMPDIR', 'TEMP', 'TMP', 'LD_LIBRARY_PATH', 'DISPLAY',
               'XDG_RUNTIME_DIR', 'QT_QPA_PLATFORM', 'ANDROID_HOME', 'ANDROID_SDK_ROOT',
               'ANDROID_USER_HOME', 'ANDROID_EMULATOR_HOME', 'ANDROID_AVD_HOME',
               'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'REQUESTS_CA_BUNDLE',
               'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
               'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy'}
    return {key: value for key, value in env.items() if key in allowed}


class OwnedApi36Vm:
    def __init__(self, env):
        require(env.get('GITHUB_ACTIONS') == 'true' and
                env.get('GITHUB_REPOSITORY') == 'JJalal1/real-estate-uat-backend' and
                env.get('GITHUB_REF') == 'refs/heads/work/phase1-native-account-20261103' and
                env.get('GITHUB_EVENT_NAME') == 'push' and
                re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', '')) is not None and
                env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA') and
                re.fullmatch('[1-9][0-9]{0,19}', env.get('GITHUB_RUN_ID', '')) is not None and
                re.fullmatch('[1-9][0-9]{0,3}', env.get('GITHUB_RUN_ATTEMPT', '')) is not None,
                'fixed_disposable_ci_context_required')
        self.env = child_environment(dict(env))
        self.sdk = Path(env['ANDROID_HOME']).resolve(strict=True)
        self.avd = Path(env['ANDROID_AVD_HOME']).resolve(strict=True)
        self.private = Path(env['RUNNER_TEMP']) / 'aqer-phase1-owned-vm'
        require(not self.private.exists() and not self.private.is_symlink(), 'fresh_vm_directory_required')
        self.private.mkdir(mode=0o700)
        self.process = None
        self.started = self.closed = False
        self._clock_preparation_used = False
        self._recording_environment_used = False
        self.receipt = {'android_api': 36, 'acceleration': 'KVM',
                        'network_modified': False, 'boot_and_CE_ready': False,
                        'vm_parent_exit_code': None, 'owned_process_group_absence_observed': False}

    def __repr__(self):
        return '<OwnedApi36Vm private disposable runtime>'

    def _observe(self, *args, deadline=None):
        timeout = 3 if deadline is None else max(0, min(3, deadline - time.monotonic()))
        if timeout <= 0:
            return None
        try:
            result = subprocess.run([str(self.sdk / 'platform-tools/adb'), '-s', 'emulator-5554',
                                     *args], env=self.env, stdin=subprocess.DEVNULL,
                                    capture_output=True, timeout=timeout)
        except (OSError, subprocess.TimeoutExpired):
            return None
        if result.returncode != 0 or result.stderr:
            return None
        try:
            return result.stdout.decode('ascii').strip()
        except UnicodeError:
            return None

    def start(self, boot_seconds=240):
        require(not self.started and not self.closed, 'vm_start_already_consumed')
        require(type(boot_seconds) is int and 1 <= boot_seconds <= 300, 'vm_boot_bound_required')
        self.started = True
        require(stat.S_ISCHR(os.stat('/dev/kvm').st_mode) and os.access('/dev/kvm', os.R_OK | os.W_OK),
                'actual_accessible_kvm_required')
        binary = self.sdk / 'emulator/emulator'
        require(binary.is_file() and os.access(binary, os.X_OK), 'official_emulator_binary_required')
        require((self.avd / 'aqer-native-account.avd/config.ini').is_file(), 'prepared_fixed_avd_required')
        try:
            devices = subprocess.run([str(self.sdk / 'platform-tools/adb'), 'devices'],
                env=self.env, stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
            lines = devices.stdout.decode('ascii').splitlines()
        except (OSError, UnicodeError, subprocess.TimeoutExpired):
            raise VmBlocked('fresh_device_absence_unobserved') from None
        require(devices.returncode == 0 and lines and lines[0] == 'List of devices attached'
                and all(not line.strip() for line in lines[1:]), 'fresh_empty_device_inventory_required')
        fd = os.open(self.private / 'emulator.log', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            self.process = subprocess.Popen([
                str(binary), '-avd', 'aqer-native-account', '-port', '5554',
                '-no-window', '-no-audio', '-no-snapshot', '-no-boot-anim',
                '-gpu', 'swiftshader', '-accel', 'on', '-memory', '2048', '-cores', '2'],
                env=self.env, stdin=subprocess.DEVNULL, stdout=fd, stderr=subprocess.STDOUT,
                start_new_session=True)
        except OSError:
            raise VmBlocked('owned_vm_start_failed') from None
        finally:
            os.close(fd)
        self.receipt['started_utc'] = datetime.now(timezone.utc).isoformat()
        until = time.monotonic() + boot_seconds
        while time.monotonic() < until:
            require(self.process.poll() is None, 'owned_vm_exited_before_readiness')
            if (self._observe('shell', 'getprop', 'sys.boot_completed', deadline=until) == '1' and
                    self._observe('shell', 'getprop', 'sys.user.0.ce_available', deadline=until) == 'true' and
                    self._observe('shell', 'getprop', 'ro.build.version.sdk', deadline=until) == '36'):
                name = self._observe('emu', 'avd', 'name', deadline=until)
                require(name is not None and name.splitlines() == ['aqer-native-account', 'OK']
                        and self.process.poll() is None, 'owned_avd_identity_unobserved')
                display = self._observe('shell', 'wm', 'size', deadline=until)
                match = re.fullmatch(r'Physical size: ([0-9]{2,5})x([0-9]{2,5})', display or '')
                physical = [int(match[1]), int(match[2])] if match else None
                self.receipt['physical_display_before_app_install'] = physical
                require(physical == [540, 960], 'owned_physical_capture_display_mismatch')
                self.receipt['boot_and_CE_ready'] = True
                return
            time.sleep(max(0, min(2, until - time.monotonic())))
        raise VmBlocked('owned_vm_boot_CE_not_ready')

    def prepare_utc_clock(self, *, deadline):
        """Set only the fresh owned emulator clock, then restore shell UID2000.

        No application is installed yet. Actual clock acceptance remains the
        unchanged later host/guest bracket check; setting is not proof of sync.
        """
        require(not self._clock_preparation_used and self.started and not self.closed
                and self.receipt['boot_and_CE_ready'] is True
                and self.process is not None and self.process.poll() is None,
                'fresh_owned_vm_clock_preparation_required')
        require(type(deadline) in (int, float) and math.isfinite(deadline)
                and deadline > time.monotonic(), 'bounded_clock_preparation_required')
        self._clock_preparation_used = True
        deadline = min(deadline, time.monotonic() + 40)
        observation = {'attempted_once': True, 'root_uid_verified': False,
                       'date_setter_exit_zero': False, 'default_shell_uid_restored': False,
                       'root_request': {'attempted_once': False, 'transport': 'NOT_ATTEMPTED', 'stderr': 'NOT_ATTEMPTED'},
                       'unroot_request': {'attempted_once': False, 'transport': 'NOT_ATTEMPTED', 'stderr': 'NOT_ATTEMPTED'},
                       'date_transport_roundtrip_ms': None, 'date_transport_compensation_ms': None,
                       'clock_acceptance_claimed': False, 'stage': 'root_request'}
        self.receipt['clock_preparation'] = observation
        def restart_request(operation):
            # Restarting adbd may disconnect its own request transport. Its
            # acknowledgment is not actual UID proof; issue it only once and
            # always leave verification to the bounded read-only UID poll.
            receipt = observation[operation + '_request']
            remaining = min(5, deadline - time.monotonic())
            if remaining <= 0 or self.process.poll() is not None:
                return
            receipt['attempted_once'] = True
            try:
                result = subprocess.run([str(self.sdk / 'platform-tools/adb'), '-s',
                    'emulator-5554', operation], env=self.env, stdin=subprocess.DEVNULL,
                    capture_output=True, timeout=remaining)
            except (OSError, subprocess.TimeoutExpired):
                receipt.update(transport='UNOBSERVED', stderr='UNOBSERVED')
                return
            receipt.update(transport='EXIT_ZERO' if result.returncode == 0 else 'EXIT_NONZERO',
                           stderr='EMPTY' if result.stderr == b'' else 'REPORTED')
        def command(*args, maximum=5):
            remaining = min(maximum, deadline - time.monotonic())
            require(remaining > 0 and self.process.poll() is None,
                    'owned_clock_preparation_deadline_or_runtime_lost')
            try:
                result = subprocess.run([str(self.sdk / 'platform-tools/adb'), '-s',
                    'emulator-5554', *args], env=self.env, stdin=subprocess.DEVNULL,
                    capture_output=True, timeout=remaining)
            except (OSError, subprocess.TimeoutExpired):
                raise VmBlocked('owned_clock_preparation_unobserved') from None
            require(result.returncode == 0 and result.stderr == b'' and len(result.stdout) <= 4096,
                    'owned_clock_preparation_unobserved')
            try:
                return result.stdout.decode('ascii').strip()
            except UnicodeError:
                raise VmBlocked('owned_clock_preparation_unobserved') from None
        def wait_uid(expected, failure_code):
            # adbd can still expose its old connection just after root/unroot.
            # Repeat only this read, never either daemon request or date setter.
            until = min(deadline, time.monotonic() + 10)
            while time.monotonic() < until:
                try:
                    read_started = time.monotonic()
                    if command('shell', 'id', '-u', maximum=min(2, until - time.monotonic())) == expected:
                        elapsed = time.monotonic() - read_started
                        require(math.isfinite(elapsed) and 0 <= elapsed <= 2,
                                'owned_clock_uid_transport_unbounded')
                        return elapsed
                except VmBlocked:
                    require(self.process.poll() is None and time.monotonic() < deadline,
                            'owned_clock_preparation_deadline_or_runtime_lost')
                time.sleep(max(0, min(.2, until - time.monotonic())))
            raise VmBlocked(failure_code)
        try:
            restart_request('root')
            observation['stage'] = 'root_uid_wait'
            root_roundtrip = wait_uid('0', 'owned_clock_root_uid_unverified')
            observation['root_uid_verified'] = True
            host_ns = time.time_ns()
            require(type(host_ns) is int and host_ns > 0, 'actual_host_utc_required')
            # Estimate one-way ADB delivery from the immediately preceding
            # successful read-only shell exchange. The later independent UTC
            # bracket still proves synchronization; this estimate grants no
            # acceptance and changes no signed expiry or retry policy.
            compensation_ns = int(root_roundtrip * 1000000000 / 2)
            observation['date_transport_roundtrip_ms'] = round(root_roundtrip * 1000)
            observation['date_transport_compensation_ms'] = round(compensation_ns / 1000000)
            host_ns += compensation_ns
            # Toybox accepts @UNIXTIME.FRACTION and -u/-s. No expiry value is
            # translated, extended or clamped, and no raw timestamp is retained.
            stamp = '@' + str(host_ns // 1000000000) + '.' + format(host_ns % 1000000000, '09d')
            observation['stage'] = 'date_set'
            command('shell', 'date', '-u', '-s', stamp)
            observation['date_setter_exit_zero'] = True
        except VmBlocked:
            observation['failure_stage'] = observation['stage']
            raise
        finally:
            try:
                observation['stage'] = 'unroot_request'
                restart_request('unroot')
                observation['stage'] = 'shell_uid_wait'
                wait_uid('2000', 'owned_default_shell_uid_unverified')
                observation['default_shell_uid_restored'] = True
            except VmBlocked:
                observation['restore_failure_stage'] = observation['stage']
                raise
        observation['stage'] = 'complete'
        return True

    def prepare_recording_environment(self, *, deadline):
        """Disable only owned user0 UI sound effects before APP installation.

        A settings readback is environment configuration, never proof that a
        future recording is silent. Its exact-zero validators remain separate.
        """
        clock = self.receipt.get('clock_preparation')
        require(not self._recording_environment_used and self.started and not self.closed
                and self.receipt['boot_and_CE_ready'] is True
                and self.process is not None and self.process.poll() is None
                and self._clock_preparation_used and type(clock) is dict
                and clock.get('stage') == 'complete'
                and all(clock.get(key) is True for key in
                    ('root_uid_verified', 'date_setter_exit_zero', 'default_shell_uid_restored')),
                'fresh_owned_recording_environment_required')
        require(type(deadline) in (int, float) and math.isfinite(deadline)
                and deadline > time.monotonic(), 'bounded_recording_environment_required')
        self._recording_environment_used = True
        deadline = min(deadline, time.monotonic() + 10)
        observation = {'attempted_once': True, 'current_android_user0_verified': False,
                       'system_sound_effects_disabled_readback': False,
                       'actual_recorded_silence_claimed': False, 'stage': 'shell_uid'}
        self.receipt['recording_environment'] = observation
        def command(*args):
            remaining = min(3, deadline - time.monotonic())
            require(remaining > 0 and self.process.poll() is None,
                    'owned_recording_environment_deadline_or_runtime_lost')
            try:
                result = subprocess.run([str(self.sdk / 'platform-tools/adb'), '-s',
                    'emulator-5554', *args], env=self.env, stdin=subprocess.DEVNULL,
                    capture_output=True, timeout=remaining)
            except (OSError, subprocess.TimeoutExpired):
                raise VmBlocked('owned_recording_environment_unobserved') from None
            require(result.returncode == 0 and result.stderr == b'' and len(result.stdout) <= 4096,
                    'owned_recording_environment_unobserved')
            try:
                value = result.stdout.decode('ascii').strip()
            except UnicodeError:
                raise VmBlocked('owned_recording_environment_unobserved') from None
            require(time.monotonic() < deadline and self.process.poll() is None,
                    'owned_recording_environment_deadline_or_runtime_lost')
            return value
        try:
            require(command('shell', 'id', '-u') == '2000', 'recording_default_shell_uid_unverified')
            observation['stage'] = 'current_user'
            require(command('shell', 'am', 'get-current-user') == '0', 'recording_current_android_user_unverified')
            observation['current_android_user0_verified'] = True
            observation['stage'] = 'system_sound_effects_put'
            command('shell', 'settings', '--user', '0', 'put', 'system', 'sound_effects_enabled', '0')
            observation['stage'] = 'system_sound_effects_get'
            require(command('shell', 'settings', '--user', '0', 'get', 'system',
                            'sound_effects_enabled') == '0', 'recording_sound_effects_readback_unverified')
            observation['system_sound_effects_disabled_readback'] = True
        except VmBlocked:
            observation['failure_stage'] = observation['stage']
            raise
        observation['stage'] = 'complete'
        return True

    def close(self, *, deadline=None):
        require(deadline is None or (type(deadline) in (int, float) and math.isfinite(deadline)),
                'bounded_vm_cleanup_deadline_required')
        if self.closed:
            return dict(self.receipt)
        self.closed = True
        process = self.process
        def remaining(maximum):
            return maximum if deadline is None else max(0, min(maximum, deadline - time.monotonic()))
        if process is not None:
            try:
                if process.poll() is None:
                    # Popen created this separate group; while its leader lives
                    # the PID/PGID cannot have been reused for another process.
                    require(os.getpgid(process.pid) == process.pid, 'owned_vm_group_identity_unobserved')
                    os.killpg(process.pid, signal.SIGTERM if remaining(8) >= 1 else signal.SIGKILL)
                    try:
                        process.wait(timeout=remaining(8))
                    except subprocess.TimeoutExpired:
                        require(process.poll() is None and os.getpgid(process.pid) == process.pid,
                                'owned_vm_group_identity_unobserved')
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait(timeout=remaining(5))
                self.receipt['vm_parent_exit_code'] = process.returncode
                # The observed parent exit can precede its process-group drain.
                # Keep the same strict absence check and bounded cleanup reserve.
                until = time.monotonic() + remaining(20)
                while True:
                    try:
                        os.killpg(process.pid, 0)
                    except ProcessLookupError:
                        self.receipt['owned_process_group_absence_observed'] = True
                        break
                    if time.monotonic() >= until:
                        break
                    time.sleep(max(0, min(.1, until - time.monotonic())))
            except (OSError, subprocess.TimeoutExpired, VmBlocked):
                self.receipt['vm_shutdown_unconfirmed'] = True
        else:
            self.receipt['owned_process_group_absence_observed'] = True
        self.receipt['ended_utc'] = datetime.now(timezone.utc).isoformat()
        return dict(self.receipt)
