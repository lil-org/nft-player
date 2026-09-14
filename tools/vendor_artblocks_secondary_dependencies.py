import argparse
import base64
import hashlib
import io
import json
import pathlib
import tarfile
import tempfile
import urllib.request


REPOSITORY = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_DESTINATION = REPOSITORY / "nft-player/Generators/newlibs"
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
)


def relative_path(value):
    path = pathlib.PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise ValueError(f"Invalid resource path: {value}")
    return path


def verify_bytes(record, data):
    if len(data) != record["bytes"]:
        raise ValueError(f"Size mismatch: {record['file']}")
    if hashlib.sha256(data).hexdigest() != record["sha256"]:
        raise ValueError(f"SHA-256 mismatch: {record['file']}")


def download(url, limit):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=90) as response:
        if response.status != 200:
            raise ValueError(f"Unexpected HTTP status {response.status}: {url}")
        data = response.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"Download exceeds expected size: {url}")
    return data


def retrieve(record, package_cache):
    if "content" in record:
        data = record["content"].encode("utf-8")
    elif "packagePath" in record:
        package_key = (record["source"], record["packageIntegrity"])
        if package_key not in package_cache:
            archive = download(record["source"], 64 * 1024 * 1024)
            integrity = "sha512-" + base64.b64encode(hashlib.sha512(archive).digest()).decode("ascii")
            if integrity != record["packageIntegrity"]:
                raise ValueError(f"Package integrity mismatch: {record['source']}")
            package_cache[package_key] = archive
        with tarfile.open(fileobj=io.BytesIO(package_cache[package_key]), mode="r:gz") as archive:
            member = archive.getmember(str(relative_path(record["packagePath"])))
            if not member.isfile():
                raise ValueError(f"Package resource is not a regular file: {record['packagePath']}")
            with archive.extractfile(member) as source:
                data = source.read(32 * 1024 * 1024 + 1)
        if record.get("extractLeadingComment"):
            data = data[data.index(b"/*") + 2:data.index(b"*/")].strip() + b"\n"
    else:
        data = download(record["source"], record["bytes"])
    verify_bytes(record, data)
    return data


def main():
    parser = argparse.ArgumentParser(description="Verify or restore the pinned Art Blocks secondary rendering dependencies.")
    parser.add_argument("--manifest", type=pathlib.Path, default=DEFAULT_DESTINATION / "manifest.json")
    parser.add_argument("--destination", type=pathlib.Path, default=DEFAULT_DESTINATION)
    parser.add_argument("--fetch", action="store_true", help="Restore missing or modified files from their pinned sources.")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    records = manifest["secondaryVendorFiles"]
    paths = [relative_path(record["file"]) for record in records]
    if len(set(paths)) != len(paths):
        raise ValueError("Duplicate secondary resource paths")

    package_cache = {}
    replacements = {}
    for record, relative in zip(records, paths):
        target = args.destination / relative
        try:
            verify_bytes(record, target.read_bytes())
        except (OSError, ValueError):
            if not args.fetch:
                raise
            replacements[relative] = retrieve(record, package_cache)

    for relative, data in replacements.items():
        target = args.destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as staging:
            staging.write(data)
            temporary = pathlib.Path(staging.name)
        temporary.replace(target)

    print(f"Verified {len(records)} secondary dependency files ({sum(record['bytes'] for record in records):,} bytes).")
    if replacements:
        print(f"Restored {len(replacements)} files from their pinned sources.")


if __name__ == "__main__":
    main()
