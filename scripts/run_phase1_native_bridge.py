#!/usr/bin/env python3
"""Frozen same-job entry. Import is inert; only explicit CLI selects work."""
from __future__ import annotations

import argparse
import base64
import contextlib
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time
import unittest

REPO = 'JJalal1/real-estate-uat-backend'
REF = 'refs/heads/work/phase1-native-account-20261103'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
SECRET = 'AQER_PHASE1_TEST_ACCESS_JSON'
MANIFEST = 'scripts/phase1_bridge/tool_manifest.json'
HELPER_SOURCE_SHA = 'aafc36e2a366a7d11f79273437d29b4adc3d76a2855fda727e6034f942b39b0e'
PAIRED_PROBE_SHA = '013c47a4e6829200a77d2c594aa0583442eea36834d71c0f7020649622c2db76'
ROOT_PUBLIC_B64 = 'JhpJ97jF4RGpskxSodJge5e1JK+usUcGdJGg9K8gInA='
ROOT_KEY_ID = '0aa9312dfaf25e6f5b5c231ef230aa859caed22a8f464e18b77eb67333250872'
EXPECTED_FILES = tuple(sorted((
    '.github/actions/phase1-review/README.md',
    '.github/actions/phase1-review/action.yml',
    '.github/actions/phase1-review/index.js',
    '.github/actions/phase1-review/package-lock.json',
    '.github/actions/phase1-review/package.json',
    '.github/actions/phase1-review/test_index.js',
    '.github/phase1-close-recipient.pem',
    '.github/workflows/phase1-native-account.yml',
    'scripts/phase1_device_input/AndroidManifest.xml',
    'scripts/phase1_device_input/Phase1Input.java',
    'scripts/phase1_native_account_readiness.py',
    'scripts/phase1_native_fixture_api.py',
    'scripts/prepare_phase1_close.py',
    'scripts/prepare_phase1_followup.py',
    'scripts/prepare_phase1_native_account.py',
    'scripts/probe_phase1_native_account.py',
    'scripts/run_phase1_native_bridge.py',
    'scripts/tests/test_phase1_native_account.py',
    'scripts/tests/test_phase1_native_account_build.py',
    'scripts/tests/test_phase1_native_account_fixture.py',
    'scripts/tests/test_phase1_native_account_readiness.py',
    'scripts/phase1_bridge/root_review_public.json',
    'scripts/phase1_bridge/protocol/review_protocol.py',
    'scripts/phase1_bridge/protocol/test_review_protocol.py',
    'scripts/phase1_bridge/protocol/README.md',
    'scripts/phase1_bridge/owner/owner_session.py',
    'scripts/phase1_bridge/owner/grants.py',
    'scripts/phase1_bridge/owner/command_transport.py',
    'scripts/phase1_bridge/owner/checkpoint_packager.py',
    'scripts/phase1_bridge/owner/checkpoint_io.py',
    'scripts/phase1_bridge/owner/test_owner_components.py',
    'scripts/phase1_bridge/owner/test_checkpoint_packager.py',
    'scripts/phase1_bridge/owner/test_checkpoint_io.py',
    'scripts/phase1_bridge/owner/README.md',
    'scripts/phase1_bridge/oneshot/oneshot_adapter.py',
    'scripts/phase1_bridge/oneshot/test_oneshot_adapter.py',
    'scripts/phase1_bridge/oneshot/README.md',
    'scripts/phase1_bridge/adapter/c1_home_capture.py',
    'scripts/phase1_bridge/adapter/c1_basics_capture.py',
    'scripts/phase1_bridge/adapter/ci_probe_adapter.py',
    'scripts/phase1_bridge/adapter/ci_remote_evidence.py',
    'scripts/phase1_bridge/adapter/build_ci_variants.py',
    'scripts/phase1_bridge/adapter/test_integration.py',
    'scripts/phase1_bridge/adapter/test_logout_home.py',
    'scripts/phase1_bridge/adapter/test_home_capture.py',
    'scripts/phase1_bridge/adapter/test_basics_capture.py',
    'scripts/phase1_bridge/adapter/README.md',
    'scripts/phase1_bridge/adapter/variants/VARIANT_MANIFEST.json',
    'scripts/phase1_bridge/adapter/variants/ci_remote_evidence.py',
    'scripts/phase1_bridge/adapter/variants/promoted_cleanup.py',
    'scripts/phase1_bridge/adapter/variants/C2_SOURCE_PROPOSAL/c2_native_roles.py',
    'scripts/phase1_bridge/adapter/variants/LOCAL_REMAINING_PROPOSAL/local_stage_policy.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py',
    'scripts/phase1_bridge/adapter/variants/ROOT_C4_EXECUTOR/phase_extensions.py',
    'scripts/phase1_bridge/adapter/variants/runtime/host_console_capture.py',
    'scripts/phase1_bridge/controller/controller.py',
    'scripts/phase1_bridge/controller/bounded_api.py',
    'scripts/phase1_bridge/controller/test_controller.py',
    'scripts/phase1_bridge/controller/test_home_diagnostic.py',
    'scripts/phase1_bridge/controller/test_bounded_api.py',
    'scripts/phase1_bridge/controller/README.md',
    'scripts/phase1_bridge/runtime/owned_vm.py',
    'scripts/phase1_bridge/runtime/test_owned_vm_review.py',
    'scripts/phase1_bridge/entry/test_entry.py',
    'scripts/phase1_bridge/entry/README.md',
)))
PUBLIC_ENV = frozenset({'GITHUB_ACTIONS', 'GITHUB_REPOSITORY', 'GITHUB_REF',
    'GITHUB_EVENT_NAME', 'GITHUB_SHA', 'SOURCE_COMMIT', 'GITHUB_RUN_ID',
    'GITHUB_RUN_ATTEMPT', 'GITHUB_RUN_NUMBER', 'GITHUB_WORKSPACE', 'GITHUB_ENV',
    'RUNNER_TEMP', 'AQER_PHASE1_NATIVE_ACCOUNT', 'UAT_API_BASE_URL',
    'AQER_BRIDGE_TOOLBUNDLE_SHA'})
CHILD_ENV = frozenset({'PATH', 'HOME', 'USER', 'LOGNAME', 'SHELL', 'LANG', 'LC_ALL',
    'LC_CTYPE', 'TZ', 'TMPDIR', 'TEMP', 'TMP', 'LD_LIBRARY_PATH', 'DISPLAY',
    'XDG_RUNTIME_DIR', 'QT_QPA_PLATFORM', 'ANDROID_HOME', 'ANDROID_SDK_ROOT',
    'ANDROID_USER_HOME', 'ANDROID_EMULATOR_HOME', 'ANDROID_AVD_HOME',
    'SSL_CERT_FILE', 'SSL_CERT_DIR', 'CURL_CA_BUNDLE', 'REQUESTS_CA_BUNDLE',
    'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
    'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy'})


class EntryBlocked(RuntimeError):
    """Only fixed diagnostics, never raw arguments/content/exception payloads."""


def need(value, code):
    if not value:
        raise EntryBlocked(code)


def pairs(items):
    result = {}
    for key, value in items:
        need(key not in result, 'duplicate_entry_json_key')
        result[key] = value
    return result


def read_owned(path, maximum, *, private=False):
    """No symlink components, FIFO, oversized value or multiply linked file."""
    path = Path(path)
    need(path.is_absolute() and '..' not in path.parts, 'absolute_entry_path_required')
    fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in path.parts[1:-1]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd); fd = child
        file_fd = os.open(path.name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=fd)
        try:
            before = os.fstat(file_fd)
            need(stat.S_ISREG(before.st_mode) and before.st_uid == os.geteuid()
                and before.st_nlink == 1 and 0 < before.st_size <= maximum,
                'owned_entry_file_required')
            need(not private or stat.S_IMODE(before.st_mode) == 0o600,
                 'private_entry_file_required')
            value = os.read(file_fd, maximum+1)
            after = os.fstat(file_fd)
            need(len(value) == before.st_size and
                (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns) ==
                (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns),
                'entry_file_changed')
            return value
        finally:
            os.close(file_fd)
    except OSError:
        raise EntryBlocked('entry_file_unobserved') from None
    finally:
        os.close(fd)


def strict_json(raw):
    try:
        value = json.loads(raw.decode('utf-8'), object_pairs_hook=pairs,
            parse_constant=lambda _: (_ for _ in ()).throw(EntryBlocked('entry_json_invalid')))
    except EntryBlocked:
        raise
    except (ValueError, UnicodeError, RecursionError):
        raise EntryBlocked('entry_json_invalid') from None
    need(type(value) is dict, 'entry_object_required')
    return value


def isolate_environment(environ):
    """Pop the two authorized channels before the first git/SDK subprocess."""
    token, raw_secret = environ.pop('GITHUB_TOKEN', None), environ.pop(SECRET, None)
    public = {key: value for key, value in environ.items() if key in PUBLIC_ENV | CHILD_ENV}
    child = {key: value for key, value in public.items() if key in CHILD_ENV}
    environ.clear(); environ.update(child)
    return public, token, raw_secret


def check_ci(env):
    need(env.get('GITHUB_ACTIONS') == 'true' and env.get('GITHUB_REPOSITORY') == REPO
        and env.get('GITHUB_REF') == REF and env.get('GITHUB_EVENT_NAME') == 'push'
        and env.get('AQER_PHASE1_NATIVE_ACCOUNT') == 'true'
        and re.fullmatch('[a-f0-9]{40}', env.get('GITHUB_SHA', ''))
        and env.get('SOURCE_COMMIT') == env.get('GITHUB_SHA')
        and all(re.fullmatch('[1-9][0-9]{0,19}', env.get(key, ''))
                for key in ['GITHUB_RUN_ID', 'GITHUB_RUN_NUMBER'])
        and re.fullmatch('[1-9][0-9]{0,2}', env.get('GITHUB_RUN_ATTEMPT', ''))
        and env.get('UAT_API_BASE_URL') == API, 'fixed_bridge_ci_context_required')


def verify_manifest(workspace, *, expected_files=EXPECTED_FILES):
    raw = read_owned(workspace / MANIFEST, 128*1024)
    manifest = strict_json(raw)
    need(set(manifest) == {'version', 'files'} and type(manifest['version']) is int
        and manifest['version'] == 1 and type(manifest['files']) is dict
        and set(manifest['files']) == set(expected_files), 'exact_tool_manifest_required')
    need(len(expected_files) == len(set(expected_files)), 'unique_expected_files_required')
    for name in sorted(expected_files):
        wanted = manifest['files'][name]
        need(type(wanted) is str and re.fullmatch('[0-9a-f]{64}', wanted), 'tool_hash_invalid')
        need(hashlib.sha256(read_owned(workspace / name, 2*1024*1024)).hexdigest() == wanted,
             'frozen_tool_bytes_mismatch')
    return hashlib.sha256(raw).hexdigest(), manifest['files']


def load(name, path):
    need(name not in sys.modules, 'fresh_entry_import_required')
    spec = importlib.util.spec_from_file_location(name, path)
    need(spec is not None and spec.loader is not None, 'frozen_module_unavailable')
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    try:
        spec.loader.exec_module(module)
    except BaseException:
        sys.modules.pop(name, None)
        raise EntryBlocked('frozen_module_load_failed') from None
    return module


def verify_paired_sources(hashes):
    need(hashes['scripts/phase1_device_input/Phase1Input.java'] == HELPER_SOURCE_SHA
        and re.fullmatch('[a-f0-9]{64}', PAIRED_PROBE_SHA)
        and hashes['scripts/probe_phase1_native_account.py'] == PAIRED_PROBE_SHA,
        'reviewed_paired_helper_source_required')


def source_guard(workspace, env):
    check_ci(env)
    need(Path(env.get('GITHUB_WORKSPACE', '')).resolve() == workspace,
         'actual_workspace_source_required')
    tool_sha, hashes = verify_manifest(workspace)
    verify_paired_sources(hashes)
    public_pin = strict_json(read_owned(workspace / 'scripts/phase1_bridge/root_review_public.json', 4096))
    need(set(public_pin) == {'algorithm', 'root_public_b64', 'root_key_id', 'scope'}
        and public_pin['algorithm'] == 'Ed25519' and public_pin['root_public_b64'] == ROOT_PUBLIC_B64
        and public_pin['root_key_id'] == ROOT_KEY_ID, 'reviewed_root_public_pin_required')
    scripts = workspace / 'scripts'
    sys.path.insert(0, str(scripts))
    guard = load('prepare_phase1_native_account', scripts / 'prepare_phase1_native_account.py')
    # This reviewed guard binds actual git HEAD, exact diff allowlist, original
    # unchanged product trees, clean tracked paths, recipient hash and expiry.
    receipt = guard.guard(env)
    need(receipt['source_commit'] == env['GITHUB_SHA'] and guard.API == API,
         'actual_source_guard_required')
    return tool_sha, guard


def export_github_env(env, tool_sha):
    path = Path(env.get('GITHUB_ENV', ''))
    root = Path(env.get('RUNNER_TEMP', ''))
    need(path.is_absolute() and root.is_absolute() and '..' not in path.parts
        and path.is_relative_to(root)
        and re.fullmatch('[0-9a-f]{64}', tool_sha), 'fixed_github_env_required')
    parent_fd = os.open('/', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        for part in path.parts[1:-1]:
            child_fd = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
            os.close(parent_fd); parent_fd = child_fd
        fd = os.open(path.name, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=parent_fd)
        try:
            info = os.fstat(fd)
            need(stat.S_ISREG(info.st_mode) and info.st_uid == os.geteuid()
                and info.st_nlink == 1 and info.st_size <= 1024*1024, 'owned_github_env_required')
            value = ('AQER_BRIDGE_TOOLBUNDLE_SHA=' + tool_sha + '\n').encode('ascii')
            need(os.write(fd, value) == len(value), 'github_env_write_unobserved')
        finally:
            os.close(fd)
    except OSError:
        raise EntryBlocked('github_env_write_unobserved') from None
    finally:
        os.close(parent_fd)


class RuntimeChecks:
    """Only fixed helper package metadata/hash and guest clock observations."""
    def __init__(self, *, sdk, child_env, helper_sha, deadline_getter,
                 runner=subprocess.run, utc_ms=lambda: time.time_ns()//1_000_000,
                 monotonic_clock=time.monotonic):
        need(set(child_env) <= CHILD_ENV, 'isolated_helper_environment_required')
        self.adb = str(Path(sdk) / 'platform-tools/adb')
        self.env, self.helper_sha = dict(child_env), helper_sha
        self.deadline, self.runner, self.utc_ms, self.mono = deadline_getter, runner, utc_ms, monotonic_clock
        self.diagnostic_sink = None

    def _diagnostic(self, check, status, **values):
        if self.diagnostic_sink is not None:
            self.diagnostic_sink(dict(check=check, status=status, **values))

    def _observe(self, args):
        remaining = self.deadline() - self.mono()
        need(remaining > 0, 'helper_observation_deadline_expired')
        try:
            result = self.runner([self.adb, '-s', 'emulator-5554', *args],
                stdin=subprocess.DEVNULL, capture_output=True, timeout=min(5, remaining), env=self.env)
        except BaseException:
            raise EntryBlocked('helper_observation_unobserved') from None
        need(result.returncode == 0 and result.stderr == b'' and len(result.stdout) <= 4096,
             'helper_observation_unobserved')
        need(self.mono() < self.deadline(), 'helper_observation_deadline_expired')
        try:
            return result.stdout.decode('ascii').strip()
        except UnicodeError:
            raise EntryBlocked('helper_observation_invalid') from None

    def verify_helper_identity(self):
        self._diagnostic('helper_identity', 'path_query')
        path = self._observe(['shell', 'pm', 'path', 'com.aqer.phase1.input'])
        need(re.fullmatch(r'package:(/data/app/[A-Za-z0-9_~=/+.-]+/base\.apk)', path),
             'single_installed_helper_required')
        installed = path.removeprefix('package:')
        need('..' not in Path(installed).parts, 'fixed_helper_apk_path_required')
        self._diagnostic('helper_identity', 'hash_query')
        observed = self._observe(['shell', 'sha256sum', installed])
        need(observed == self.helper_sha + '  ' + installed,
             'actual_installed_helper_hash_mismatch')
        self._diagnostic('helper_identity', 'verified')
        return True

    def verify_guest_utc(self):
        self._diagnostic('guest_utc', 'clock_query')
        before = self.utc_ms()
        mono_before = self.mono()
        observed = self._observe(['shell', 'date', '-u', '+%s%3N'])
        after = self.utc_ms()
        elapsed_ms = (self.mono() - mono_before) * 1000
        valid_format = re.fullmatch('[0-9]{13}', observed) is not None
        def bounded(value):
            return int(round(value)) if type(value) in (int, float) and math.isfinite(value) and abs(value) <= 1000000 else None
        self._diagnostic('guest_utc', 'observed', format_valid=valid_format,
            elapsed_ms=bounded(elapsed_ms),
            wall_elapsed_ms=bounded(after-before) if type(before) is int and type(after) is int else None,
            offset_low_ms=bounded(int(observed)-after) if valid_format and type(after) is int else None,
            offset_high_ms=bounded(int(observed)-before) if valid_format and type(before) is int else None)
        need(type(before) is int and type(after) is int and 0 <= after-before <= 2000
            and 0 <= elapsed_ms <= 2000 and abs((after-before)-elapsed_ms) <= 100
            and re.fullmatch('[0-9]{13}', observed), 'guest_utc_observation_invalid')
        guest = int(observed)
        # A real bracket bounds network/scheduling latency; allow at most250ms
        # host/guest offset, never a five-second unsafe deadline extension.
        need(after-250 <= guest <= before+250, 'actual_guest_host_utc_unsynchronized')
        self._diagnostic('guest_utc', 'verified')
        return True


def authority_deadline(owner):
    active = owner.active_authority
    # Root/source leases already carry the work cap. Cleanup deliberately uses
    # the separate reserved deadline even after the work budget has expired.
    return active.monotonic_deadline if active is not None else owner.work_deadline


def current_private_aliases(probe):
    values = set(probe.private_values)
    api = getattr(probe, 'fixture_api', None)
    if api is not None:
        values.update(getattr(api, '_private_values', ()))
    return tuple(sorted(value for value in values if type(value) is str and value))


class LivePrivacyPackager:
    """Fresh RAM alias refusal in addition to the frozen packager's schema.

    Credentials themselves are never included in the argument object checked
    here; only current known aliases are used to reject accidental inclusion.
    """
    def __init__(self, packager, aliases):
        self._packager, self._aliases = packager, aliases

    @property
    def identity(self): return self._packager.identity

    @property
    def max_allocated(self): return self._packager.max_allocated

    def seal(self, **kwargs):
        try:
            encoded = json.dumps(kwargs, ensure_ascii=False, sort_keys=True,
                                 separators=(',', ':'), allow_nan=False)
        except (TypeError, ValueError, UnicodeError):
            raise EntryBlocked('private_boundary_json_invalid') from None
        need(not any(alias in encoded for alias in self._aliases()),
             'private_boundary_value_refused')
        return self._packager.seal(**kwargs)

    def close(self): return self._packager.close()


def runtime_close(vm, *, deadline):
    observed = vm.close(deadline=deadline)
    created = vm.process is not None
    code = observed.get('vm_parent_exit_code')
    group = observed.get('owned_process_group_absence_observed') is True
    ended = group and ((created and type(code) is int) or (not created and code is None))
    return {'vm_created': created, 'relay_created': False,
        'vm_exit_code': code if type(code) is int else None, 'relay_exit_code': None,
        'owned_process_group_absence_observed': group,
        'all_created_processes_observed_ended': ended}


def load_runtime(workspace):
    scripts, bridge = workspace / 'scripts', workspace / 'scripts/phase1_bridge'
    for relative in ['protocol', 'owner', 'oneshot', 'adapter', 'adapter/variants', 'controller', 'runtime']:
        sys.path.insert(0, str(bridge / relative))
    # Import the codec from the top-level adapter exactly once. Its variant
    # copy is byte-pinned too, but never creates a second freshness class/module.
    codec = load('ci_remote_evidence', bridge / 'adapter/ci_remote_evidence.py')
    readiness = load('phase1_native_account_readiness', scripts / 'phase1_native_account_readiness.py')
    fixture = load('phase1_native_fixture_api', scripts / 'phase1_native_fixture_api.py')
    base = load('probe_phase1_native_account', scripts / 'probe_phase1_native_account.py')
    c4 = load('_bridge_c4', bridge / 'adapter/variants/ROOT_C4_EXECUTOR/phase_extensions.py')
    c2 = load('_bridge_c2', bridge / 'adapter/variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py')
    dispatch = load('_bridge_dispatch', bridge / 'adapter/variants/ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py')
    import review_protocol, grants, owner_session, command_transport, checkpoint_packager, checkpoint_io
    import ci_probe_adapter, controller, owned_vm
    capture = load('_bridge_capture', bridge / 'adapter/variants/runtime/host_console_capture.py')
    need(base.ROOT == workspace and base.API == API and fixture.API == API,
         'fixed_source_runtime_paths_required')
    return locals()


def run_native(workspace, env, channels, run_root, tool_sha, guard):
    need(type(channels) is list and len(channels) == 2, 'one_runtime_channel_handoff_required')
    token, raw_secret = channels.pop(0), channels.pop(0)
    need(type(token) is str and token and type(raw_secret) is str and raw_secret,
         'authorized_runtime_channels_required')
    need(env.get('AQER_BRIDGE_TOOLBUNDLE_SHA') == tool_sha, 'verified_toolbundle_env_required')
    wanted_root = Path(env['RUNNER_TEMP']) / ('aqer-phase1-bridge-' + env['GITHUB_RUN_ID'] + '-' + env['GITHUB_RUN_ATTEMPT'])
    need(run_root == wanted_root and not run_root.is_symlink(), 'fixed_fresh_run_root_required')
    info = run_root.stat()
    need(stat.S_ISDIR(info.st_mode) and stat.S_IMODE(info.st_mode) == 0o700
        and info.st_uid == os.geteuid() and not list(run_root.iterdir()), 'fresh_private_run_root_required')
    os.umask(0o077)
    m = load_runtime(workspace)
    owner_module, grants = m['owner_session'], m['grants']
    public = m['review_protocol'].Ed25519PublicKey.from_public_bytes(base64.b64decode(ROOT_PUBLIC_B64, validate=True))
    private = workspace / 'phase1-native-account-private'
    proof = strict_json(read_owned(private / 'APK_VERIFICATION.json', 128*1024))
    helper_sha = proof.get('input_driver', {}).get('sha256')
    need(proof.get('source_commit') == env['GITHUB_SHA'] and proof.get('package') == m['base'].APP
        and type(helper_sha) is str and re.fullmatch('[a-f0-9]{64}', helper_sha)
        and hashlib.sha256(read_owned(private / 'input.apk', 4*1024*1024, private=True)).hexdigest() == helper_sha,
        'prepared_source_bound_helper_required')
    need(not (workspace / 'phase1-native-account-evidence').exists(), 'fresh_private_evidence_required')
    child_env = {key: value for key, value in env.items() if key in CHILD_ENV}
    holder = {}
    authority = lambda: holder['owner'].active_authority
    context = lambda: holder['owner'].current_context
    def deadline():
        return authority_deadline(holder['owner'])
    checks = RuntimeChecks(sdk=env['ANDROID_HOME'], child_env=child_env,
                          helper_sha=helper_sha, deadline_getter=deadline)
    ProbeBase = m['ci_probe_adapter'].make_probe_class(base_class=m['base'].NativeAccount,
        host_capture_mixin=m['capture'].HostConsoleCaptureMixin,
        validate_access=m['base'].validate_access, secret_name=SECRET,
        install_known_roles=m['c2'].roles.install_known_roles,
        authority_types=(grants.VerifiedGrant, grants.SourcePlanLease, grants.CleanupLease),
        app=m['base'].APP, activity=m['base'].ACTIVITY, helper=m['base'].HELPER)
    class BoundedProbe(ProbeBase):
        def command(self, args, timeout=90, **kwargs):
            remaining = deadline() - time.monotonic()
            need(remaining > 0 and type(timeout) in (int, float) and math.isfinite(timeout)
                and timeout > 0, 'probe_command_deadline_expired')
            return super().command(args, timeout=min(timeout, remaining), **kwargs)
    probe_env = dict(env, **{SECRET: raw_secret})
    try:
        probe = BoundedProbe(private, probe_env, authority_getter=authority, context_getter=context,
            verify_helper_identity=checks.verify_helper_identity, verify_guest_utc=checks.verify_guest_utc)
    finally:
        probe_env.pop(SECRET, None)
        raw_secret = None
    probe.private_values.add(token)  # RAM-only protocol/packager redaction too.
    def readiness_diagnostic(value):
        rows = probe.report.setdefault('native_readiness_observations', [])
        need(len(rows) < 128, 'bounded_readiness_diagnostics_required')
        rows.append(value)
        probe.save()
    checks.diagnostic_sink = readiness_diagnostic
    need('GITHUB_TOKEN' not in probe.env and SECRET not in probe.env,
         'probe_environment_isolation_required')
    vm = m['owned_vm'].OwnedApi36Vm(env)
    def boot(*, deadline):
        remaining = math.floor(deadline - time.monotonic())
        need(remaining > 0, 'vm_boot_deadline_expired')
        vm.start(boot_seconds=min(240, remaining))
        need(vm.receipt.get('boot_and_CE_ready') is True and vm.process is not None
            and vm.process.poll() is None, 'actual_owned_vm_readiness_required')
        need(vm.prepare_utc_clock(deadline=deadline) is True,
             'owned_vm_clock_preparation_required')
        probe.report['owned_vm_clock_preparation'] = dict(vm.receipt['clock_preparation'])
        probe.save()
        need(vm.prepare_recording_environment(deadline=deadline) is True,
             'owned_vm_recording_environment_required')
        probe.report['owned_vm_recording_environment'] = dict(vm.receipt['recording_environment'])
        probe.save()
    def close_owned_runtime(*, deadline):
        receipt = runtime_close(vm, deadline=deadline)
        probe.report['owned_vm_lifecycle'] = dict(vm.receipt)
        probe.save()
        return receipt
    class LiveAliasController(m['controller'].Controller):
        def private_aliases(self): return current_private_aliases(probe)
    controller = LiveAliasController(probe=probe, c4=m['c4'], c2=m['c2'], dispatcher=m['dispatch'],
        fixture_api_class=m['base'].FixtureApi, public_reference_reader=m['base'].read_public_reference,
        boot_runtime=boot, close_runtime=close_owned_runtime,
        authority_getter=authority, context_getter=context,
        work_deadline_getter=lambda: holder['owner'].work_deadline)
    job_key = m['review_protocol'].JobEphemeralKey()
    underlying = m['checkpoint_packager'].CheckpointPackager(root=run_root, evidence_root=probe.out,
        identity={'repo': REPO, 'run_id': env['GITHUB_RUN_ID'], 'run_attempt': int(env['GITHUB_RUN_ATTEMPT']),
            'source_sha': env['GITHUB_SHA'], 'toolbundle_sha': tool_sha},
        recipient_cert=workspace / guard.close.RECIPIENT, recipient_sha256=guard.close.RECIPIENT_SHA256,
        job_public=job_key.public(), root_key_id=ROOT_KEY_ID,
        private_aliases=controller.private_aliases())
    packager = LivePrivacyPackager(underlying, controller.private_aliases)
    channel = m['command_transport'].CommandChannel(env['GITHUB_RUN_ID'], int(env['GITHUB_RUN_ATTEMPT']), token)
    io_bridge = m['checkpoint_io'].StdIOBridge(root=run_root)
    session = owner_module.OwnerSession(root=run_root, controller=controller, channel=channel,
        packager=packager, job_key=job_key, root_public=public, checkpoint_io=io_bridge)
    holder['owner'] = session
    signal.signal(signal.SIGTERM, session.request_stop)
    signal.signal(signal.SIGINT, session.request_stop)
    # Legacy phase modules print safe receipts. The action control channel must
    # contain only StdIOBridge's direct fixed os.write messages, so suppress all
    # ordinary Python/library output and traceback payloads for the whole run.
    with open(os.devnull, 'w') as sink, contextlib.redirect_stdout(sink), contextlib.redirect_stderr(sink):
        result = session.run()
    return 0 if (result.reason_code == 'COLLECTED_PENDING_ROOT_ACCEPTANCE'
        and result.collected and result.cleanup_confirmed and result.runtime_ended) else 1


def offline_tests(workspace):
    bridge = workspace / 'scripts/phase1_bridge'
    for folder in ['protocol', 'owner', 'oneshot', 'adapter', 'controller', 'runtime', 'entry']:
        sys.path.insert(0, str(bridge / folder))
    tests = [('protocol', 'test_review_protocol'), ('owner', 'test_owner_components'),
        ('owner', 'test_checkpoint_packager'), ('owner', 'test_checkpoint_io'),
        ('oneshot', 'test_oneshot_adapter'), ('controller', 'test_bounded_api'),
        ('controller', 'test_controller'), ('runtime', 'test_owned_vm_review'), ('entry', 'test_entry'),
        ('adapter', 'test_logout_home'), ('adapter', 'test_home_capture'),
        ('controller', 'test_home_diagnostic'), ('adapter', 'test_basics_capture')]
    suite = unittest.TestSuite()
    for _, name in tests:
        suite.addTests(unittest.defaultTestLoader.loadTestsFromName(name))
    # This original source-reproduction test requires the offline source bundle
    # not deployed to CI. Every other adapter runtime contract remains included.
    module = __import__('test_integration')
    for item in unittest.defaultTestLoader.loadTestsFromModule(module):
        for case in item:
            if case._testMethodName != 'test_all_clock_sites_adapted_original_hashes_and_capture_unchanged':
                suite.addTest(case)
    with open(os.devnull, 'w') as sink:
        result = unittest.TextTestRunner(stream=sink, verbosity=0).run(suite)
    if not result.wasSuccessful():
        # Offline tests use only synthetic values. Emit bounded test identifiers,
        # never traceback/exception content, so CI differences are diagnosable.
        for case, _ in result.failures + result.errors:
            identifier = case.id()
            if re.fullmatch(r'[A-Za-z0-9_.]{1,240}', identifier):
                print('AQER_BRIDGE_OFFLINE_TEST_FAILED_' + identifier, file=sys.stderr)
    need(result.wasSuccessful(), 'bridge_offline_contract_tests_failed')
    return result.testsRun


def main(argv=None):
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--source-only', action='store_true')
    modes.add_argument('--offline-tests', action='store_true')
    modes.add_argument('--run-root', type=Path)
    parser.add_argument('--github-env', action='store_true')
    args = parser.parse_args(argv)
    env, token, raw_secret = isolate_environment(os.environ)
    workspace = Path(__file__).resolve().parents[1]
    try:
        need(not args.github_env or args.source_only, 'github_env_source_only_required')
        if args.offline_tests:
            # No credentials, git/SDK/device/network operation is needed here.
            _, hashes = verify_manifest(workspace)
            verify_paired_sources(hashes)
            count = offline_tests(workspace)
            print('AQER_BRIDGE_OFFLINE_TESTS_PASS_' + str(count))
            return 0
        tool_sha, guard = source_guard(workspace, env)
        if args.source_only:
            if args.github_env:
                export_github_env(env, tool_sha)
            print('AQER_BRIDGE_FROZEN_SOURCE_VERIFIED')
            return 0
        channels = [token, raw_secret]
        token = raw_secret = None
        return run_native(workspace, env, channels, args.run_root, tool_sha, guard)
    except BaseException:
        # No command, exception, raw role/value, API state or traceback leaves.
        print('AQER_BRIDGE_ENTRY_BLOCKED', file=sys.stderr)
        return 1
    finally:
        token = raw_secret = None


if __name__ == '__main__':
    raise SystemExit(main())
