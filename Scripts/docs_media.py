"""Import only the reviewed CI fixtures. Requires Python 3 and authenticated gh."""

import argparse
from datetime import datetime
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

REPO = "bobs-org/bob-mac-capture"
# Artifact stem, stable documentation stem, synthetic fixture identity.
CURATED = (
    ("agenda-agenda-current-760", "capture-agenda",
     "CaptureAgendaDesignTests / Tests/Fixtures/agenda-current.json"),
    ("task-complete-task-complete-strike-760", "task-completion",
     "TaskCompleteDesignTests / Tests/Fixtures/task-complete-strike.json"),
    ("refs-browse-880", "refs-browse",
     "RefsPanelDesignTests / makeFixture(now:) / renderBrowse"),
)
APPEARANCES = ("light", "dark")


def gh(*args):
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(
            f"gh {' '.join(args[:2])} failed; check gh authentication and artifact access: "
            f"{result.stderr.strip()}"
        )
    return result.stdout


def latest_run():
    runs = json.loads(gh(
        "run", "list", "--repo", REPO, "--workflow", "ci.yml",
        "--branch", "master", "--status", "success", "--limit", "1",
        "--json", "databaseId,headSha,createdAt,url,status,conclusion,headBranch",
    ))
    if not runs:
        raise ValueError("no successful ci.yml run on master")
    run = runs[0]
    if (run["status"], run["conclusion"], run["headBranch"]) != (
        "completed", "success", "master"
    ):
        raise ValueError("selected CI run is not a completed success on master")
    run_id = str(run["databaseId"])
    if not run_id.isdecimal() or not re.fullmatch(r"[0-9a-f]{40}", run["headSha"]):
        raise ValueError("selected CI run has invalid ID or full commit SHA")
    if run["url"] != f"https://github.com/{REPO}/actions/runs/{run_id}":
        raise ValueError("selected CI run URL does not match its repository and ID")
    date = datetime.fromisoformat(run["createdAt"].replace("Z", "+00:00"))
    if date.tzinfo is None:
        raise ValueError("selected CI run date has no timezone")
    return run


def validate_png(path):
    """Reject truncated/corrupt PNG chunks before touching committed assets."""
    if path.is_symlink() or not path.is_file():
        raise ValueError(f"required curated image is missing or not a regular file: {path.name}")
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError(f"invalid PNG: {path.name}")
    offset, image_data, header = 8, False, False
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        end = offset + 12 + length
        if end > len(data):
            break
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:end - 4]
        crc = struct.unpack(">I", data[end - 4:end])[0]
        if zlib.crc32(kind + payload) != crc:
            break
        if not header:
            if kind != b"IHDR" or length != 13 or not all(struct.unpack(">II", payload[:8])):
                break
            header = True
        if kind == b"IDAT":
            image_data = True
        if kind == b"IEND":
            if length == 0 and end == len(data) and image_data:
                return
            break
        offset = end
    raise ValueError(f"truncated or corrupt PNG: {path.name}")


def import_media(root):
    run = latest_run()
    run_id = str(run["databaseId"])
    pages = json.loads(gh(
        "api", "--paginate", "--slurp",
        f"repos/{REPO}/actions/runs/{run_id}/artifacts",
    ))
    artifacts = [a for page in pages for a in page["artifacts"]
                 if a["name"] == "render-fixtures"]
    if len(artifacts) != 1 or artifacts[0].get("expired") is not False:
        raise ValueError(f"render-fixtures is missing or expired for CI run {run_id}")

    docs = root / "docs"
    # Download, validate, and build the entire replacement on the same filesystem.
    with tempfile.TemporaryDirectory(prefix=".docs-media-", dir=docs) as raw:
        stage = Path(raw)
        downloaded = stage / "download"
        gh("run", "download", run_id, "--repo", REPO,
           "--name", "render-fixtures", "--dir", str(downloaded))
        images = stage / "images"
        images.mkdir()
        manifest = {}
        for artifact_stem, dest_stem, fixture in CURATED:
            for appearance in APPEARANCES:
                original = f"{artifact_stem}-{appearance}.png"
                path = downloaded / original
                validate_png(path)
                suffix = "" if appearance == "light" else "-dark"
                dest = f"{dest_stem}{suffix}.png"
                shutil.copyfile(path, images / dest)
                manifest[f"images/{dest}"] = {
                    "source": (
                        f"Synthetic CI render fixture; {fixture}; artifact render-fixtures/"
                        f"{original}; run {run_id} {run['url']}; commit {run['headSha']}; "
                        f"created {run['createdAt']}"
                    ),
                    "date": run["createdAt"][:10],
                }
        # JSON is a YAML subset; keep the existing source/date-only schema.
        staged_manifest = stage / "media.yml"
        staged_manifest.write_text(json.dumps(manifest, indent=2) + "\n")
        replace_outputs(docs, images, staged_manifest, stage)
    print(f"docs-media: imported {len(manifest)} synthetic renders from {run['url']}")


def replace_outputs(docs, images, manifest, stage):
    """Roll back both outputs if a filesystem replacement fails."""
    installed, backups = [], []
    try:
        for staged, dest in ((images, docs / "images"), (manifest, docs / "media.yml")):
            if dest.is_symlink():
                raise ValueError(f"refusing to replace symlink: {dest}")
            if dest.exists():
                backup = stage / f"old-{dest.name}"
                dest.rename(backup)
                backups.append((backup, dest))
            staged.rename(dest)
            installed.append(dest)
    except Exception:
        for dest in reversed(installed):
            if dest.is_dir():
                shutil.rmtree(dest)
            else:
                dest.unlink()
        for backup, dest in reversed(backups):
            backup.rename(dest)
        raise


def main():
    parser = argparse.ArgumentParser(
        description="Import curated synthetic renders from the latest successful master CI run.",
        epilog="Requires Python 3 and authenticated gh. Owns docs/images/ and docs/media.yml.",
    )
    parser.parse_args()
    try:
        import_media(Path(__file__).resolve().parent.parent)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print(f"docs-media: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
