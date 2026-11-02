#!/usr/bin/env python3
"""Explicit dispatch/task-branch offline startup; never a live-UAT acceptance."""
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zlib

PACKAGE = 'com.aqer.yemen.uat'
TEST_PACKAGE = PACKAGE + '.test'
TEST_RUNNER = 'com.example.real_estate_mobile.Phase1UiInstrumentation'
TEST_CLASS = ('com.example.real_estate_mobile.Phase1FirstRunReadinessTest,'
              'com.example.real_estate_mobile.Phase1UiStartupTest')
SCREENSHOT = '/data/user/0/' + PACKAGE + '/cache/phase1-ui-startup.png'
API = 'https://real-estate-uat-api-frankfurt.onrender.com/api'
ROOT = Path(__file__).resolve().parents[1]
LIMITS = ['offline startup only', 'no account or live UAT journey',
          'no handset, FCM, provider, or upgrade acceptance']
TASK_REPOSITORY = 'JJalal1/real-estate-uat-backend'
TASK_REF = 'refs/heads/work/phase1-ui-diagnosis-20261102'


class GateError(RuntimeError):
    """Only fixed diagnostic codes, never command output or credentials."""

    def __init__(self, code, diagnostics=None):
        super().__init__(code)
        self.diagnostics = diagnostics


UI_STAGES = frozenset([
    'runner_bootstrap', 'runner_junit_start',
    'target_identity', 'ui_automation', 'activity_launch', 'first_run_wait',
    'navigation_before_capture', 'frame_capture', 'navigation_after_capture',
    'frame_validation', 'frame_write', 'observation_report',
])
UI_EXCEPTIONS = frozenset([
    'AssertionError', 'RuntimeException', 'IllegalStateException',
    'IllegalArgumentException', 'NullPointerException', 'SecurityException',
    'UnsupportedOperationException', 'TimeoutException',
    'ClassNotFoundException', 'NoClassDefFoundError', 'UnsatisfiedLinkError',
    'IOException', 'FileNotFoundException',
    'VerifyError', 'ExceptionInInitializerError', 'NoSuchMethodError',
    'AbstractMethodError', 'IncompatibleClassChangeError',
])
UI_MISSING_CLASSES = frozenset([
    'androidx.tracing.Trace', 'androidx.tracing.TraceApi18Impl',
    'androidx.test.runner.AndroidJUnitRunner', 'androidx.test.runner.MonitoringInstrumentation',
    'androidx.test.platform.app.InstrumentationRegistry',
    'androidx.test.platform.io.PlatformTestStorageRegistry',
    'androidx.test.services.storage.TestStorage',
    'androidx.test.internal.runner.RunnerArgs',
    'androidx.test.internal.platform.app.ActivityInvoker',
    'androidx.test.core.app.ApplicationProvider',
    'androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry',
    'androidx.lifecycle.ProcessLifecycleInitializer', 'androidx.lifecycle.ReportFragment',
    'androidx.lifecycle.LifecycleOwner', 'androidx.lifecycle.LifecycleEventObserver',
    'androidx.core.app.CoreComponentFactory',
    'androidx.startup.InitializationProvider', 'androidx.startup.AppInitializer',
    'io.flutter.embedding.android.FlutterActivity', 'io.flutter.embedding.android.FlutterView',
    'io.flutter.embedding.engine.FlutterJNI',
    'com.example.real_estate_mobile.AqerApplication',
    'com.example.real_estate_mobile.MainActivity',
])


def instrumentation_diagnostics(output, stderr=None):
    """Discard all messages, stack frames, UI text and unknown diagnostic values."""
    def text(value):
        return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
    output = text(output) + '\n' + text(stderr)
    stages = re.findall(r'^INSTRUMENTATION_STATUS: aqer_ui_stage=([a-z_]+)\s*$', output, re.M)
    classes = re.findall(r'\b(?:java\.(?:lang|io|util\.concurrent)\.)?([A-Z][A-Za-z]+(?:Exception|Error))\b', output)
    result = {'last_stage': next((s for s in reversed(stages) if s in UI_STAGES), 'unreported'),
              'exception_types': sorted(set(classes) & UI_EXCEPTIONS)}
    signals = [code for code, text in [
        ('process_crashed', 'Process crashed.'),
        ('runner_not_registered', 'Unable to find instrumentation info'),
        ('instrumentation_security_denied', 'Permission Denial: starting instrumentation'),
        ('runner_not_instantiated', 'Unable to instantiate instrumentation'),
        ('native_fatal_signal', 'Fatal signal'),
        ('junit_failed', 'FAILURES!!!'),
    ] if text in output]
    if signals:
        result['signals'] = signals
    # Only exact known symbols may escape. A namespace-looking value is still
    # arbitrary input, so all other names become one fixed signal.
    missing = re.findall(r'(?:Didn.t find class [\"\']|Failed resolution of: L)'
                         r'([A-Za-z0-9_.$/]{1,180})(?:[\"\']|;)', output)
    if missing:
        names = {name.replace('/', '.') for name in missing}
        if names & UI_MISSING_CLASSES:
            result['missing_classes'] = sorted(names & UI_MISSING_CLASSES)[:8]
        if names - UI_MISSING_CLASSES:
            result.setdefault('signals', []).append('unclassified_missing_class')
    return result


def validate_proof(proof, apk_bytes, source, run_number):
    expected = {'source_commit': source, 'package': PACKAGE, 'api': API,
                'version_code': 1000 + run_number, 'package_role': 'current-uat',
                'zip_crc': 'passed', 'apksigner': 'passed',
                'native_16kb_elf': 'passed', 'zipalign_16kb': 'passed'}
    if any(proof.get(k) != v for k, v in expected.items()):
        raise GateError('apk_proof_mismatch')
    if (proof.get('bytes') != len(apk_bytes) or
            proof.get('sha256') != hashlib.sha256(apk_bytes).hexdigest() or
            not re.fullmatch(r'[a-f0-9]{64}', proof.get('certificate_sha256', ''))):
        raise GateError('apk_bytes_or_certificate_mismatch')


def validate_badging(badging, package, version=None, release=False):
    match = re.search(r"^package: name='([^']+)' versionCode='([0-9]*)'", badging, re.M)
    if not match or match[1] != package or (version is not None and match[2] != str(version)):
        raise GateError('installed_artifact_identity_mismatch')
    if release and re.search(r'^\s*application-debuggable\b', badging, re.M):
        raise GateError('debug_apk_cannot_replace_release')


def validate_instrumentation(output, version):
    if (not re.search(r'\bOK \(7 tests\)', output) or
            any(s in output for s in ['FAILURES!!!', 'INSTRUMENTATION_FAILED', 'INSTRUMENTATION_ABORTED'])):
        raise GateError('ui_instrumentation_failed', instrumentation_diagnostics(output))
    counts = re.findall(r'^INSTRUMENTATION_STATUS: aqer_junit=(\{[^\n]+\})\s*$', output, re.M)
    if len(counts) != 1:
        raise GateError('missing_junit_counts')
    counts = json.loads(counts[0])
    expected = {'run': 7, 'failures': 0, 'ignored': 0, 'assumptions': 0}
    if counts != expected or any(type(value) is not int for value in counts.values()):
        raise GateError('all_seven_tests_must_execute_and_pass')
    rows = re.findall(r'^INSTRUMENTATION_STATUS: aqer_ui_smoke=(\{[^\n]+\})\s*$', output, re.M)
    if len(rows) != 1:
        raise GateError('missing_ui_observation')
    observation = json.loads(rows[0])
    if (observation.get('package') != PACKAGE or observation.get('version_code') != version or
            observation.get('flutter_view') is not True or observation.get('nonuniform_frame') is not True or
            any(observation.get(key) is not True for key in ['first_run_continued', 'navigation_stable', 'capture_rechecked']) or
            observation.get('semantic_keys') != ['marketplace', 'account']):
        raise GateError('flutter_ui_not_observed')
    return observation


def validate_png(data):
    """Validate complete native RGB/RGBA PNG scanlines, including CRC and IDAT."""
    if not data.startswith(b'\x89PNG\r\n\x1a\n') or len(data) > 20 * 1024 * 1024:
        raise GateError('invalid_png')
    offset, header, compressed, ended = 8, None, bytearray(), False
    while offset + 12 <= len(data):
        size = struct.unpack_from('>I', data, offset)[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 12 + size
        if end > len(data):
            raise GateError('truncated_png')
        payload = data[offset + 8:end - 4]
        if zlib.crc32(kind + payload) & 0xffffffff != struct.unpack_from('>I', data, end - 4)[0]:
            raise GateError('png_crc_mismatch')
        if kind == b'IHDR':
            if header is not None or offset != 8 or size != 13:
                raise GateError('invalid_png_header')
            header = struct.unpack('>IIBBBBB', payload)
        elif kind == b'IDAT':
            compressed.extend(payload)
        elif kind == b'IEND':
            ended = size == 0 and end == len(data)
            break
        offset = end
    if not header or not ended or not compressed:
        raise GateError('incomplete_png')
    width, height, depth, color, compression, filtering, interlace = header
    if not (0 < width <= 4096 and 0 < height <= 4096 and depth == 8 and color in (2, 6) and
            compression == filtering == interlace == 0):
        raise GateError('unsupported_png_frame')
    stride = width * (3 if color == 2 else 4) + 1
    expected = stride * height
    decoder = zlib.decompressobj()
    try:
        pixels = decoder.decompress(compressed, expected + 1)
    except zlib.error:
        raise GateError('invalid_png_compression') from None
    if (len(pixels) != expected or not decoder.eof or decoder.unused_data or decoder.unconsumed_tail or
            any(pixels[i] > 4 for i in range(0, expected, stride))):
        raise GateError('invalid_png_scanlines')
    return {'width': width, 'height': height, 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def execute(argv, binary=False, timeout=120):
    return subprocess.run(argv, capture_output=True, text=not binary, timeout=timeout)


def enabled(env):
    explicit_activation = (env.get('GITHUB_EVENT_NAME') == 'workflow_dispatch' or
                           (env.get('GITHUB_EVENT_NAME') == 'push' and
                            env.get('GITHUB_REPOSITORY') == TASK_REPOSITORY and env.get('GITHUB_REF') == TASK_REF))
    return (env.get('GITHUB_ACTIONS') == 'true' and explicit_activation and
            env.get('AQER_ANDROID_UI_SMOKE') == 'true')


def probe(root, env, run=execute):
    if not enabled(env):
        raise GateError('manual_opt_in_required')
    source, number = env.get('SOURCE_COMMIT', ''), env.get('GITHUB_RUN_NUMBER', '')
    if not re.fullmatch(r'[a-f0-9]{40}', source) or source != env.get('GITHUB_SHA') or not number.isdigit():
        raise GateError('invalid_source_or_run')
    proof = json.loads((root / 'dist/APK_VERIFICATION.json').read_text())
    apk = root / f'dist/real-estate-broker-uat-{number}.apk'
    tests = root / 'android-release-tests/tests.apk'
    validate_proof(proof, apk.read_bytes(), source, int(number))
    pair = json.loads((tests.parent / 'PAIR_VERIFICATION.json').read_text())
    if (pair.get('source_commit') != source or pair.get('variant') != 'uatReleaseAndroidTest' or
            pair.get('runner') != TEST_RUNNER or
            pair.get('release_sha256') != proof['sha256'] or
            pair.get('tests_sha256') != hashlib.sha256(tests.read_bytes()).hexdigest()):
        raise GateError('release_test_pair_identity_mismatch')

    def command(argv, label, binary=False, codes=(0,), timeout=120):
        try:
            result = run([str(a) for a in argv], binary=binary, timeout=timeout)
        except subprocess.TimeoutExpired as exc:
            diagnostic = instrumentation_diagnostics(exc.stdout, exc.stderr) if label == 'ui_instrumentation' else None
            raise GateError(label + '_timeout', diagnostic) from None
        if result.returncode not in codes:
            diagnostic = instrumentation_diagnostics(result.stdout, result.stderr) if label == 'ui_instrumentation' else None
            raise GateError(label + '_failed', diagnostic)
        return result.stdout if binary else result.stdout.strip()

    sdk = Path(env['ANDROID_HOME'])
    if 'KVM' not in command([sdk / 'emulator/emulator', '-accel-check'], 'kvm'):
        raise GateError('kvm_required')
    tools = sorted((sdk / 'build-tools').glob('*/apksigner'))
    if not tools:
        raise GateError('android_build_tools_missing')
    signer, aapt = tools[-1], tools[-1].parent / 'aapt'
    for path, package, version in [(apk, PACKAGE, proof['version_code']), (tests, TEST_PACKAGE, None)]:
        signed = command([signer, 'verify', '--print-certs', path], 'apk_signature')
        digest = re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})', signed)
        if not digest or digest[1].lower() != proof['certificate_sha256']:
            raise GateError('test_and_release_signers_must_match')
        validate_badging(command([aapt, 'dump', 'badging', path], 'apk_badging'), package,
                         version=version, release=package == PACKAGE)
    devices = command(['adb', 'devices'], 'adb_devices')
    serials = re.findall(r'^(emulator-[0-9]+)\s+device\s*$', devices, re.M)
    if len(serials) != 1:
        raise GateError('one_ready_emulator_required')
    serial = serials[0]

    def adb(*args, **kwargs):
        return command(['adb', '-s', serial, *args], 'adb_' + str(args[0]), **kwargs)

    if (adb('shell', 'getprop', 'ro.build.version.sdk') != '36' or
            adb('shell', 'getprop', 'sys.boot_completed') != '1' or
            adb('shell', 'getprop', 'ro.boot.qemu') != '1' or adb('shell', 'id', '-u') != '0'):
        raise GateError('booted_disposable_api36_emulator_required')
    for package in [PACKAGE, TEST_PACKAGE]:
        if adb('shell', 'pm', 'path', package, codes=(0, 1)):
            raise GateError('fresh_install_required')
    blocks, installed, failure, result = [], [], None, None
    try:
        for tool in ['iptables', 'ip6tables']:
            check = run(['adb', '-s', serial, 'shell', tool, '-C', 'OUTPUT', '-j', 'REJECT'])
            if check.returncode != 1:
                raise GateError('clean_offline_firewall_required')
            adb('shell', tool, '-I', 'OUTPUT', '1', '-j', 'REJECT')
            blocks.append(tool)
        for path, package in [(apk, PACKAGE), (tests, TEST_PACKAGE)]:
            adb('install', '-t', str(path), timeout=180)
            installed.append(package)
        # This is the already validated disposable emulator. Clear only its
        # synthetic crash buffer so old push tests cannot contaminate diagnosis.
        adb('logcat', '-b', 'crash', '-c')
        output = command(['adb', '-s', serial, 'shell', 'am', 'instrument', '-w', '-r',
                          TEST_PACKAGE + '/' + TEST_RUNNER],
                         'ui_instrumentation', timeout=90)
        seen = validate_instrumentation(output, proof['version_code'])
        png = adb('exec-out', 'cat', SCREENSHOT, binary=True)
        image = validate_png(png)
        if (image['width'], image['height']) != (seen.get('width'), seen.get('height')):
            raise GateError('screenshot_observation_mismatch')
        result = ({'status': 'passed', 'scope': 'isolated-offline-release-startup',
                   'source_commit': source, 'package': PACKAGE, 'version_code': proof['version_code'],
                   'apk_sha256': proof['sha256'], 'certificate_sha256': proof['certificate_sha256'],
                   'instrumentation_variant': pair['variant'], 'tests_sha256': pair['tests_sha256'],
                   'instrumentation_runner': TEST_RUNNER,
                   'junit_counts': {'run': 7, 'failures': 0, 'ignored': 0, 'assumptions': 0},
                   'android_api': 36, 'serial': serial, 'ipv4_ipv6_egress_rejected': True,
                   'flutter_view': True, 'semantic_keys': ['marketplace', 'account'], 'image': image,
                   'first_run_continued': True, 'navigation_stable': True, 'capture_rechecked': True,
                   'limitations': LIMITS}, png)
    except Exception as exc:
        failure = exc if isinstance(exc, GateError) else GateError('unexpected_probe_error')
        if str(failure).startswith('ui_instrumentation'):
            try:
                crash = adb('logcat', '-d', '-b', 'crash', '-v', 'brief', timeout=10)
                safe = instrumentation_diagnostics(crash)
                # Export fixed codes and exact allowlisted symbols only.
                # The crash buffer itself is never saved or logged.
                if safe['exception_types'] or safe.get('signals') or safe.get('missing_classes'):
                    failure.diagnostics = {**(failure.diagnostics or {}), 'fresh_runtime_crash': safe}
            except Exception:
                failure.diagnostics = {**(failure.diagnostics or {}), 'runtime_diagnostics_unavailable': True}
    finally:
        cleanup_failed = False
        for package in reversed(installed):
            try:
                adb('shell', 'am', 'force-stop', package)
                adb('uninstall', package)
            except Exception:
                cleanup_failed = True
        for tool in reversed(blocks):
            try:
                adb('shell', tool, '-D', 'OUTPUT', '-j', 'REJECT')
            except Exception:
                cleanup_failed = True
    if cleanup_failed:
        raise GateError((str(failure) + '_and_' if failure else '') + 'cleanup_failed',
                        getattr(failure, 'diagnostics', None))
    if failure:
        raise failure
    return result


def main():
    if not enabled(os.environ):
        print('AQER_PHASE1_UI_SMOKE_REFUSED_MANUAL_OPT_IN_REQUIRED')
        return 2
    output = ROOT / 'android-ui-evidence'
    # Refuse stale evidence; only these two newly generated files may be uploaded.
    output.mkdir()
    try:
        report, image = probe(ROOT, os.environ)
        (output / 'startup.png').write_bytes(image)
    except Exception as exc:
        report = {'status': 'failed', 'failure': str(exc) if isinstance(exc, GateError) else 'unexpected_error',
                  'scope': 'isolated-offline-release-startup', 'limitations': LIMITS}
        if isinstance(exc, GateError) and exc.diagnostics is not None:
            report['diagnostics'] = exc.diagnostics
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    # The upload step cannot export a stale directory or evidence from an earlier run.
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as handle:
            handle.write('phase1_ui_evidence=true\n')
    print('AQER_PHASE1_UI_SMOKE_' + report['status'].upper() +
          (':' + report['failure'] if 'failure' in report else ''))
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
