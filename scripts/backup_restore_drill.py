#!/usr/bin/env python3
"""Network-isolated synthetic PostgreSQL + media recovery drill. NEVER targets UAT.

No DSN, password, API key, remote restore flag, or production data is accepted.
Real UAT backup/restore remains a separate owner-gated operation.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import tarfile
import tempfile
import time


def run(args, *, data=None, output=None, check=True):
    result = subprocess.run(args, input=data, stdout=output or subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=180)
    if check and result.returncode:
        # All inputs are synthetic, but still keep stderr out of public logs.
        raise RuntimeError(f"drill command failed: {args[0]} ({result.returncode})")
    return result


def sql(container, statement, check=True):
    return run(['docker', 'exec', '-i', container, 'psql', '-X', '-qAt',
                '-U', 'postgres', '-d', 'recovery_drill', '-v', 'ON_ERROR_STOP=1'],
               data=statement.encode(), check=check)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        while chunk := source.read(1024 * 1024):
            value.update(chunk)
    return value.hexdigest()


def snapshot(container):
    statement = """
    SELECT json_build_object(
      'owners',(SELECT json_agg(row_to_json(t) ORDER BY id) FROM owners t),
      'listings',(SELECT json_agg(row_to_json(t) ORDER BY id) FROM listings t),
      'objects',(SELECT json_agg(row_to_json(t) ORDER BY id) FROM storage.objects t),
      'rls',(SELECT relrowsecurity FROM pg_class WHERE oid='listings'::regclass),
      'anon_select',has_table_privilege('anon','listings','SELECT'),
      'authenticated_select',has_table_privilege('authenticated','listings','SELECT'),
      'constraints',(SELECT count(*) FROM pg_constraint WHERE conrelid='listings'::regclass),
      'sequence',(SELECT last_value FROM owners_id_seq),
      'postgis',postgis_lib_version());
    """
    return json.loads(sql(container, statement).stdout)


def extract_verified(archive, target):
    # Do not trust archive paths, symlinks, devices, or hardlinks on restore.
    with tarfile.open(archive, 'r:gz') as bundle:
        for member in bundle:
            relative = Path(member.name)
            if relative.is_absolute() or '..' in relative.parts or not member.isfile():
                raise RuntimeError('unsafe recovery archive entry')
            path = target / relative
            path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            with bundle.extractfile(member) as source, path.open('xb') as dest:
                while chunk := source.read(1024 * 1024):
                    dest.write(chunk)
            path.chmod(0o600)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', required=True, type=Path)
    parser.add_argument('--image', default='postgis/postgis:17-3.5')
    args = parser.parse_args()
    # Deliberately restrict the image; a caller cannot point this at a service.
    if args.image != 'postgis/postgis:17-3.5':
        parser.error('only the approved disposable PostgreSQL image is supported')
    os.umask(0o077)
    started = time.monotonic()
    suffix = secrets.token_hex(6)
    source, target = f'aqer-drill-source-{suffix}', f'aqer-drill-restore-{suffix}'
    containers = [source, target]
    try:
        for name in containers:
            run(['docker', 'run', '-d', '--name', name, '--network', 'none',
                 '--memory', '384m', '--cpus', '1',
                 '-e', 'POSTGRES_HOST_AUTH_METHOD=trust',
                 '-e', 'POSTGRES_DB=recovery_drill', args.image])
            deadline = time.monotonic() + 45
            while run(['docker', 'exec', name, 'pg_isready', '-U', 'postgres',
                       '-d', 'recovery_drill'], check=False).returncode:
                if time.monotonic() > deadline:
                    raise RuntimeError('disposable database readiness deadline')
                time.sleep(0.2)
        with tempfile.TemporaryDirectory(prefix='aqer-encrypted-drill-') as temp:
            root = Path(temp)
            package = root / 'package'
            package.mkdir(mode=0o700)
            media = package / 'media'
            media.mkdir(mode=0o700)
            # Include a >6MiB object and binary bytes; a metadata-only copy fails.
            for name, size in [('original.bin', 6 * 1024 * 1024 + 3), ('derivative.bin', 17003)]:
                (media / name).write_bytes(secrets.token_bytes(size))
            sql(source, """
              CREATE ROLE anon NOLOGIN; CREATE ROLE authenticated NOLOGIN;
              CREATE EXTENSION IF NOT EXISTS postgis;
              CREATE EXTENSION IF NOT EXISTS pgcrypto;
              CREATE SCHEMA storage;
              CREATE TABLE owners(id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, name text NOT NULL);
              CREATE TABLE listings(id bigint PRIMARY KEY, owner_id bigint NOT NULL REFERENCES owners,
                revision integer NOT NULL CHECK(revision>=0), point geography(Point,4326));
              ALTER TABLE owners ENABLE ROW LEVEL SECURITY;
              ALTER TABLE listings ENABLE ROW LEVEL SECURITY;
              REVOKE ALL ON owners,listings FROM PUBLIC,anon,authenticated;
              CREATE TABLE storage.objects(id integer PRIMARY KEY,bucket text NOT NULL,
                path text UNIQUE NOT NULL,sha256 text NOT NULL,bytes bigint NOT NULL);
              ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
              REVOKE ALL ON storage.objects FROM PUBLIC,anon,authenticated;
              INSERT INTO owners(name) VALUES('synthetic-owner-a'),('synthetic-owner-b');
              INSERT INTO listings VALUES(7,1,3,ST_SetSRID(ST_MakePoint(44.2,15.3),4326));
            """)
            objects = []
            for index, path in enumerate(sorted(media.iterdir()), 1):
                objects.append({'path': f'media/{path.name}', 'sha256': digest(path), 'bytes': path.stat().st_size})
                sql(source, f"INSERT INTO storage.objects VALUES({index},'private-synthetic','{path.name}','{digest(path)}',{path.stat().st_size});")
            before = snapshot(source)
            with (package / 'database.dump').open('wb') as output:
                run(['docker', 'exec', source, 'pg_dump', '-U', 'postgres',
                     '-d', 'recovery_drill', '--format=custom'], output=output)
            globals_sql = run(['docker', 'exec', source, 'pg_dumpall', '-U', 'postgres',
                               '--globals-only', '--no-role-passwords']).stdout
            (package / 'globals.sql').write_bytes(globals_sql)
            manifest = objects + [{'path': name, 'sha256': digest(package / name),
                                   'bytes': (package / name).stat().st_size}
                                  for name in ['database.dump', 'globals.sql']]
            (package / 'manifest.json').write_text(json.dumps(manifest, sort_keys=True))
            plain = root / 'recovery.tar.gz'
            with tarfile.open(plain, 'w:gz') as archive:
                for path in sorted(package.rglob('*')):
                    if path.is_file():
                        archive.add(path, arcname=str(path.relative_to(package)), recursive=False)
            key = root / 'ephemeral-identity.txt'
            run(['age-keygen', '-o', str(key)])
            key.chmod(0o600)
            recipient = run(['age-keygen', '-y', str(key)]).stdout.decode().strip()
            encrypted = root / 'recovery.tar.gz.age'
            run(['age', '-r', recipient, '-o', str(encrypted), str(plain)])
            plain.unlink()
            for path in package.rglob('*'):
                if path.is_file(): path.unlink()
            decrypted = root / 'restored.tar.gz'
            run(['age', '-d', '-i', str(key), '-o', str(decrypted), str(encrypted)])
            restored = root / 'independent-restore'
            restored.mkdir(mode=0o700)
            extract_verified(decrypted, restored)
            for entry in json.loads((restored / 'manifest.json').read_text()):
                path = restored / entry['path']
                if digest(path) != entry['sha256'] or path.stat().st_size != entry['bytes']:
                    raise RuntimeError('restored bytes do not match manifest')
            # The bootstrap role exists in an empty target cluster. This exact
            # synthetic-only mapping is not a mapping for Supabase managed roles.
            globals_restore = (restored / 'globals.sql').read_text().replace('CREATE ROLE postgres;', '')
            sql(target, globals_restore)
            run(['docker', 'exec', '-i', target, 'pg_restore', '-U', 'postgres',
                 '-d', 'recovery_drill', '--clean', '--if-exists', '--exit-on-error'], data=(restored / 'database.dump').read_bytes())
            after = snapshot(target)
            if before != after or after['anon_select'] or after['authenticated_select'] or not after['rls']:
                raise RuntimeError('database or permission fingerprint differs')
            if sql(target, 'SET ROLE anon; SELECT * FROM listings;', check=False).returncode == 0:
                raise RuntimeError('anon unexpectedly read restored listings')
            if sql(target, 'INSERT INTO listings(id,owner_id,revision) VALUES(8,999,0);', check=False).returncode == 0:
                raise RuntimeError('restored foreign key was not enforced')
            # age authentication must reject tampering; never restore such data.
            corrupt = bytearray(encrypted.read_bytes())
            corrupt[len(corrupt)//2] ^= 1
            tampered = root / 'tampered.age'
            tampered.write_bytes(corrupt)
            if run(['age', '-d', '-i', str(key), '-o', str(root/'invalid.tar'), str(tampered)], check=False).returncode == 0:
                raise RuntimeError('ciphertext authentication did not reject tampering')
            evidence = {
                'schema_version': 1, 'synthetic_only': True, 'uat_accessed': False,
                'network': 'none', 'separate_database_containers': True,
                'postgres_version': sql(source, 'SHOW server_version;').stdout.decode().strip(),
                'database_snapshot_equal': before == after, 'media_sha256_equal': True,
                'private_role_denial_verified': True, 'foreign_key_verified': True,
                'identity_sequence_verified': True, 'ciphertext_tamper_rejected': True,
                'media_objects': len(objects), 'media_bytes': sum(o['bytes'] for o in objects),
                'encrypted_bytes': encrypted.stat().st_size, 'age_identity_persisted': False,
                'elapsed_seconds': round(time.monotonic()-started, 3),
                'live_uat_backup_gate_satisfied': False,
            }
            args.evidence.parent.mkdir(parents=True, exist_ok=True)
            args.evidence.write_text(json.dumps(evidence, indent=2)+'\n')
            print(json.dumps(evidence, sort_keys=True))
    finally:
        for name in containers:
            run(['docker', 'rm', '-f', '-v', name], check=False)


if __name__ == '__main__':
    main()
