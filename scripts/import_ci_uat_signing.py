#!/usr/bin/env python3
"""Import an existing, pinned UAT key in phase23 CI; never create signing keys.

The build step supplies the same three password/alias secrets independently.
Only a generated path and public flags are appended to GITHUB_ENV. Optional
absence leaves disposable UAT builds unchanged; --required forbids that case.
JKS and PKCS12 are supported; PKCS12 store/key passwords must be identical.
"""
import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


REPOSITORY = 'JJalal1/real-estate-uat-backend'
BRANCH = 'refs/heads/work/phase23-acceptance-20261111'
INPUTS = (
    'AQER_UAT_KEYSTORE_BASE64', 'AQER_RELEASE_STORE_PASSWORD',
    'AQER_RELEASE_KEY_ALIAS', 'AQER_RELEASE_KEY_PASSWORD',
    'AQER_UAT_SIGNING_CERT_SHA256',
)
MAX_KEYSTORE_BYTES = 1024 * 1024
STAGING_DIRECTORY = 'aqer-uat-signing'
KEYSTORE_FILENAME = 'uat-release.keystore'


class SigningError(ValueError):
    """Only fixed, non-secret reason codes are allowed in this exception."""


def clean_single_line(value, maximum=4096):
    return (isinstance(value, str) and 0 < len(value) <= maximum and
            not any(ord(char) < 32 or ord(char) == 127 for char in value))


def read_configuration(env, required=False):
    """Validate inputs without touching disk. None denotes optional absence."""
    values = [env.get(name, '') for name in INPUTS]
    if env.get('AQER_RELEASE_STORE_FILE'):
        raise SigningError('conflicting_store_file')
    if not any(values):
        if required:
            raise SigningError('required_signing_not_configured')
        return None
    if not all(values):
        raise SigningError('incomplete_signing_configuration')
    encoded, store_password, alias, key_password, fingerprint = values
    if not all(clean_single_line(value) and value.strip() for value in (store_password, key_password)):
        raise SigningError('invalid_signing_credentials')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}', alias):
        raise SigningError('invalid_signing_alias')
    if not (re.fullmatch(r'[0-9A-Fa-f]{64}', fingerprint) or
            re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}', fingerprint)):
        raise SigningError('invalid_certificate_pin')
    if len(encoded) > 4 * ((MAX_KEYSTORE_BYTES + 2) // 3):
        raise SigningError('keystore_too_large')
    try:
        raw = base64.b64decode(encoded, validate=True)
    except (ValueError, binascii.Error):
        raise SigningError('invalid_keystore_encoding') from None
    if not raw or len(raw) > MAX_KEYSTORE_BYTES:
        raise SigningError('invalid_keystore_size')
    return {'keystore': raw, 'store_password': store_password, 'alias': alias,
            'key_password': key_password, 'fingerprint': fingerprint.replace(':', '').lower()}


def guard(env):
    if not (env.get('GITHUB_ACTIONS') == 'true' and
            env.get('GITHUB_REPOSITORY') == REPOSITORY and
            env.get('GITHUB_REF') == BRANCH and
            env.get('GITHUB_EVENT_NAME') == 'push' and
            env.get('AQER_SIGNING_ENVIRONMENT') == 'uat'):
        raise SigningError('explicit_phase23_uat_ci_context_required')


def safe_absolute_path(value):
    if not clean_single_line(value):
        raise SigningError('unsafe_runner_path')
    path = Path(value)
    if not path.is_absolute():
        raise SigningError('unsafe_runner_path')
    return path


def owned_regular_file(fd):
    info = os.fstat(fd)
    return (stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and
            info.st_nlink == 1 and not info.st_mode & 0o022)


def open_runner_paths(env):
    """Open existing trusted runner paths without following symlinks."""
    root = safe_absolute_path(env.get('RUNNER_TEMP', ''))
    output = safe_absolute_path(env.get('GITHUB_ENV', ''))
    if root.resolve(strict=True) != root or output.parent.resolve(strict=True) != output.parent:
        raise SigningError('symlink_runner_path')
    if not output.is_relative_to(root) or output == root:
        raise SigningError('environment_file_outside_runner_temp')
    root_fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    output_fd = None
    try:
        info = os.fstat(root_fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise SigningError('unsafe_runner_directory')
        output_fd = os.open(output, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_NONBLOCK)
        if not owned_regular_file(output_fd):
            raise SigningError('unsafe_environment_file')
        return root, root_fd, output_fd
    except BaseException:
        if output_fd is not None:
            os.close(output_fd)
        os.close(root_fd)
        raise


def validate_keystore(path, config):
    """Pin the certificate and prove private-key access without CLI passwords."""
    executable = shutil.which('keytool')
    if not executable:
        raise SigningError('keytool_unavailable')
    # Do not inherit the encoded key, unrelated CI secrets, or Java option hooks.
    child_env = {'PATH': os.defpath, 'LANG': 'C', 'LC_ALL': 'C',
                 'AQER_RELEASE_STORE_PASSWORD': config['store_password'],
                 'AQER_RELEASE_KEY_PASSWORD': config['key_password']}
    common = ['-keystore', str(path),
              '-storepass:env', 'AQER_RELEASE_STORE_PASSWORD']

    def invoke(arguments):
        try:
            result = subprocess.run([executable, '-J-Duser.language=en', '-J-Duser.country=US',
                                     *arguments, *common],
                                    env=child_env, stdin=subprocess.DEVNULL,
                                    capture_output=True, timeout=30, check=False)
        except (OSError, subprocess.SubprocessError):
            raise SigningError('keystore_validation_failed') from None
        # keytool diagnostics can contain aliases and paths: never expose them.
        if result.returncode != 0 or not result.stdout or len(result.stdout) > 65536:
            raise SigningError('keystore_validation_failed')
        return result.stdout

    listing = invoke(['-list']).decode('utf-8', errors='replace')
    store_type = re.match(r'\AKeystore type: (JKS|PKCS12)\r?\n', listing)
    if not store_type:
        raise SigningError('unsupported_keystore_type')
    # OpenJDK keytool silently ignores a differing PKCS12 key password. Reject
    # that case explicitly instead of accepting credentials Gradle cannot use.
    if store_type.group(1) == 'PKCS12' and config['key_password'] != config['store_password']:
        raise SigningError('pkcs12_password_mismatch')
    certificate = invoke(['-exportcert', '-alias', config['alias']])
    if hashlib.sha256(certificate).hexdigest() != config['fingerprint']:
        raise SigningError('certificate_pin_mismatch')
    # Certificate-only entries cannot create a CSR. JKS checks the key password
    # separately; PKCS12 key passwords must match its store-password convention.
    invoke(['-certreq', '-alias', config['alias'], '-keypass:env', 'AQER_RELEASE_KEY_PASSWORD'])


def import_signing(env, required=False):
    config = read_configuration(env, required=required)
    if config is None:
        return {'uat_signing_configured': False}
    guard(env)
    root, root_fd, output_fd = open_runner_paths(env)
    stage_fd = None
    created_directory = False
    created_key = False
    complete = False
    try:
        # Never reuse or delete an earlier job's directory, even if empty.
        os.mkdir(STAGING_DIRECTORY, mode=0o700, dir_fd=root_fd)
        created_directory = True
        stage_fd = os.open(STAGING_DIRECTORY, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                           dir_fd=root_fd)
        os.fchmod(stage_fd, 0o700)
        key_fd = os.open(KEYSTORE_FILENAME, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                         0o600, dir_fd=stage_fd)
        created_key = True
        with os.fdopen(key_fd, 'wb') as staged:
            os.fchmod(staged.fileno(), 0o600)
            staged.write(config['keystore'])
        path = root / STAGING_DIRECTORY / KEYSTORE_FILENAME
        validate_keystore(path, config)
        payload = ('\nAQER_UAT_SIGNING_CONFIGURED=true\n'
                   f'AQER_RELEASE_STORE_FILE={path}\n'
                   f"AQER_UAT_SIGNING_CERT_SHA256={config['fingerprint']}\n"
                   'AQER_ALLOW_DEBUG_RELEASE_SIGNING=false\n').encode('utf-8')
        # No write occurs until all validation passes. A failed append fails the
        # job and removes the key, so subsequent steps cannot use a partial key.
        offset = 0
        while offset < len(payload):
            count = os.write(output_fd, payload[offset:])
            if count <= 0:
                raise SigningError('environment_export_failed')
            offset += count
        complete = True
        return {'uat_signing_configured': True,
                'certificate_sha256': config['fingerprint'], 'scope': 'uat'}
    finally:
        try:
            if not complete:
                if created_key:
                    os.unlink(KEYSTORE_FILENAME, dir_fd=stage_fd)
                if created_directory:
                    os.rmdir(STAGING_DIRECTORY, dir_fd=root_fd)
        finally:
            if stage_fd is not None:
                os.close(stage_fd)
            os.close(output_fd)
            os.close(root_fd)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--required', action='store_true',
                        help='Reject absent signing configuration instead of leaving the build unchanged.')
    args = parser.parse_args(argv)
    try:
        receipt = import_signing(os.environ, required=args.required)
    except (SigningError, OSError, ValueError):
        # Never render exceptions from keytool, the OS, credentials, or paths.
        print('UAT signing configuration rejected; no credentials logged.', file=sys.stderr)
        return 1
    print(json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == '__main__':
    sys.exit(main())
