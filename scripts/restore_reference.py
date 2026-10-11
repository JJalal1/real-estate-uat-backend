#!/usr/bin/env python3
"""Verify and optionally extract the immutable, inspect-only eBroker reference."""
import argparse
import hashlib
import json
import os
import re
import stat
import tempfile
import zipfile
from pathlib import Path, PurePosixPath


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    path = PurePosixPath(name)
    return bool(name) and not path.is_absolute() and ".." not in path.parts and "\\" not in name and not re.match(r"^[A-Za-z]:", name)


def restore(root, destination=None):
    index = json.loads((root / "reference-index.json").read_text())
    if index.get("schema") != 1 or index.get("reference_only") is not True:
        raise ValueError("Unsupported reference metadata")
    spec = index["sanitized_archive"]
    if digest((root / "SOURCE_INDEX.tsv").read_bytes()) != spec["source_index_sha256"]:
        raise ValueError("Source index checksum mismatch")
    with tempfile.TemporaryDirectory(prefix="ebroker-reference-") as working:
        joined = Path(working) / "reference.zip"
        seen_parts = set()
        with joined.open("wb") as stream:
            for part in spec["parts"]:
                name = part["path"]
                if not safe_name(name) or name in seen_parts:
                    raise ValueError("Unsafe or duplicate part path")
                seen_parts.add(name)
                source = root / name
                if source.is_symlink() or not source.is_file():
                    raise ValueError("Missing or symbolic archive part")
                data = source.read_bytes()
                blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                if len(data) != part["bytes"] or digest(data) != part["sha256"] or blob != part["git_blob_sha"]:
                    raise ValueError("Archive part checksum mismatch: " + name)
                stream.write(data)
        archive_bytes = joined.read_bytes()
        if len(archive_bytes) != spec["bytes"] or digest(archive_bytes) != spec["sha256"]:
            raise ValueError("Joined archive checksum mismatch")
        with zipfile.ZipFile(joined) as archive:
            names = set()
            entries = archive.infolist()
            if sum(i.file_size for i in entries) > 128 * 1024 * 1024:
                raise ValueError("Unexpected expanded reference size")
            for entry in entries:
                if not safe_name(entry.filename) or entry.filename in names or entry.flag_bits & 1 or stat.S_ISLNK(entry.external_attr >> 16) or entry.is_dir():
                    raise ValueError("Unsafe, encrypted or duplicate ZIP member")
                names.add(entry.filename)
            manifest_bytes = archive.read("audit/file-manifest.json")
            if digest(manifest_bytes) != spec["file_manifest_sha256"]:
                raise ValueError("Audit manifest checksum mismatch")
            manifest = json.loads(manifest_bytes)
            retained = [item for item in manifest["files"] if item["included"]]
            expected = {item["reference_path"] for item in retained}
            if len(retained) != index["retained_source_files"] or len(expected) != len(retained):
                raise ValueError("Retained file count or path uniqueness mismatch")
            if names != expected | {"audit/file-manifest.json"}:
                raise ValueError("Reference membership mismatch")
            for item in retained:
                data = archive.read(item["reference_path"])
                if len(data) != item["bytes"] or digest(data) != item["sha256"]:
                    raise ValueError("Retained source checksum mismatch")
            if archive.testzip() is not None:
                raise ValueError("ZIP CRC verification failed")
            if destination is not None:
                destination = destination.absolute()
                if destination.exists() or destination.is_symlink():
                    raise ValueError("Destination already exists; refusing overwrite")
                destination.parent.mkdir(parents=True, exist_ok=True)
                with tempfile.TemporaryDirectory(prefix=".ebroker-extract-", dir=destination.parent) as staging:
                    stage = Path(staging) / "verified"
                    stage.mkdir()
                    for entry in entries:
                        target = stage / entry.filename
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(archive.read(entry))
                    if destination.exists() or destination.is_symlink():
                        raise ValueError("Destination appeared during extraction")
                    os.rename(stage, destination)
        return {"verified": True, "source_files": len(retained), "app_version": index["app_version"], "archive_sha256": spec["sha256"], "extracted": destination is not None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--destination", type=Path, default=Path("ebroker-reference"))
    args = parser.parse_args()
    try:
        print(json.dumps(restore(args.root, None if args.verify_only else args.destination)))
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print("Reference verification FAILED: " + str(error))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
