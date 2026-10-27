"""Offline behavior tests for documentation scripts; no Swift or extra packages."""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib

SCRIPTS = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("docs_media", SCRIPTS / "docs_media.py")
MEDIA = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MEDIA)
RUN = {
    "databaseId": 123, "headSha": "a" * 40, "createdAt": "2026-10-19T21:51:45Z",
    "url": "https://github.com/bobs-org/bob-mac-capture/actions/runs/123",
    "status": "completed", "conclusion": "success", "headBranch": "master",
}


def png():
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data)))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(b"\0\xff\xff\xff"))
            + chunk(b"IEND", b""))


class ScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mac docs test ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.mac = self.root / "Mac Capture"
        (self.mac / "Scripts").mkdir(parents=True)
        (self.mac / "docs/images").mkdir(parents=True)
        for name in ("docs-media.sh", "docs_media.py", "docs-check.sh"):
            shutil.copyfile(SCRIPTS / name, self.mac / "Scripts" / name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ)
        self.env.pop("BOB_CLI_DIR", None)
        self.env.update(
            PATH=f"{self.bin}{os.pathsep}{self.env['PATH']}",
            TEST_ROOT=str(self.root), XDG_CACHE_HOME=str(self.root / "cache"),
        )
        self.stub("gh", """
import json, os, pathlib, shutil, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
args = sys.argv[1:]
with (root / "gh.log").open("a") as log:
    log.write(json.dumps(args) + "\\n")
mode = os.environ.get("GH_MODE", "")
if mode == "auth":
    sys.stderr.write("authentication required")
    sys.exit(7)
if args[:2] == ["run", "list"]:
    print((root / "runs.json").read_text())
elif args[0] == "api":
    artifacts = [] if mode == "missing-artifact" else [
        {"name": "render-fixtures", "expired": mode == "expired"}]
    print(json.dumps([{"artifacts": artifacts}]))
elif args[:2] == ["run", "download"]:
    if mode == "download-fail":
        sys.exit(9)
    shutil.copytree(root / "fixtures", args[args.index("--dir") + 1])
else:
    sys.exit(99)
""")
        self.stub("just", """
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
(root / "just.json").write_text(json.dumps({
    "cwd": os.getcwd(), "args": sys.argv[1:],
    "source": os.environ.get("BOB_DOCS_BOB_MAC_CAPTURE_DIR"),
}))
sys.exit(int(os.environ.get("JUST_EXIT", "0")))
""")
        # All git use is intercepted, including unexpected network operations.
        self.stub("git", """
import os, pathlib, sys
root = pathlib.Path(os.environ["TEST_ROOT"])
args = sys.argv[1:]
with (root / "git.log").open("a") as log:
    log.write(" ".join(args) + "\\n")
if "clone" in args:
    dest = pathlib.Path(args[-1])
    for name in ("justfile", "tools/docs/pyproject.toml", "docs/_meta/mounts.yml"):
        path = dest / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
elif "get-url" in args:
    print(os.environ.get("GIT_ORIGIN", "https://github.com/bobs-org/bob-cli"))
elif "rev-parse" in args:
    print("b" * 40)
elif "fetch" not in args and "reset" not in args:
    sys.exit(99)
""")
        (self.root / "runs.json").write_text(json.dumps([RUN]))
        self.fixtures = self.root / "fixtures"
        self.fixtures.mkdir()
        for stem, _, _ in MEDIA.CURATED:
            for appearance in MEDIA.APPEARANCES:
                (self.fixtures / f"{stem}-{appearance}.png").write_bytes(png())
        (self.mac / "docs/images/previous.png").write_bytes(b"previous image")
        (self.mac / "docs/media.yml").write_text("previous: manifest\n")

    def stub(self, name, body):
        path = self.bin / name
        path.write_text("#!/usr/bin/env python3\n" + body)
        path.chmod(0o755)

    def run_script(self, name, **env):
        return subprocess.run(
            ["bash", str(self.mac / "Scripts" / name)],
            cwd=self.root, env={**self.env, **env}, capture_output=True, text=True,
        )

    def cli(self, path):
        for name in ("justfile", "tools/docs/pyproject.toml", "docs/_meta/mounts.yml"):
            item = path / name
            item.parent.mkdir(parents=True, exist_ok=True)
            item.touch()
        return path

    def outputs(self):
        return {str(p.relative_to(self.mac)): p.read_bytes()
                for p in (self.mac / "docs").rglob("*") if p.is_file()}

    def test_import_selection_provenance_and_manifest_parity(self):
        result = self.run_script("docs-media.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        manifest = json.loads((self.mac / "docs/media.yml").read_text())
        self.assertEqual(set(manifest), {
            f"images/{dest}{'' if a == 'light' else '-dark'}.png"
            for _, dest, _ in MEDIA.CURATED for a in MEDIA.APPEARANCES
        })
        self.assertEqual(set(manifest), {
            str(p.relative_to(self.mac / "docs"))
            for p in (self.mac / "docs/images").iterdir()
        })
        for stem, dest, fixture in MEDIA.CURATED:
            for a in MEDIA.APPEARANCES:
                entry = manifest[f"images/{dest}{'' if a == 'light' else '-dark'}.png"]
                self.assertEqual(set(entry), {"source", "date"})
                self.assertEqual(entry["date"], "2026-10-19")
                for fact in (RUN["url"], RUN["headSha"], RUN["createdAt"],
                             f"{stem}-{a}.png", fixture, "Synthetic"):
                    self.assertIn(fact, entry["source"])
        commands = [json.loads(line) for line in (self.root / "gh.log").read_text().splitlines()]
        self.assertIn(["--workflow", "ci.yml"], [commands[0][i:i+2] for i in range(len(commands[0]))])
        for option, value in (("--branch", "master"), ("--status", "success"), ("--limit", "1")):
            self.assertEqual(commands[0][commands[0].index(option) + 1], value)
        self.assertEqual(commands[-1][2], "123")
        self.assertEqual(commands[-1][commands[-1].index("--name") + 1], "render-fixtures")
        before = self.outputs()
        self.assertEqual(self.run_script("docs-media.sh").returncode, 0)
        self.assertEqual(self.outputs(), before)

    def test_failed_import_preserves_every_previous_output(self):
        before = self.outputs()
        for mode, message in (
            ("auth", "authentication"), ("missing-artifact", "missing or expired"),
            ("expired", "missing or expired"), ("download-fail", "failed"),
        ):
            with self.subTest(mode=mode):
                result = self.run_script("docs-media.sh", GH_MODE=mode)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(self.outputs(), before)
        selected = next(self.fixtures.iterdir())
        for data, message in ((None, "required curated image"), (b"bad", "invalid PNG"),
                              (png()[:-1], "truncated or corrupt")):
            with self.subTest(message=message):
                if data is None:
                    selected.unlink()
                else:
                    selected.write_bytes(data)
                result = self.run_script("docs-media.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertEqual(self.outputs(), before)

    def test_no_successful_run_and_invalid_metadata_preserve_outputs(self):
        before = self.outputs()
        for runs in ([], [{**RUN, "headBranch": "feature"}],
                     [{**RUN, "conclusion": "failure"}], [{**RUN, "headSha": "abc"}],
                     [{**RUN, "url": RUN["url"] + "4"}]):
            with self.subTest(runs=runs):
                (self.root / "runs.json").write_text(json.dumps(runs))
                result = self.run_script("docs-media.sh")
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.outputs(), before)

    def test_replacement_rolls_back_if_second_output_cannot_be_replaced(self):
        # A symlink refuses replacement after images have been swapped.
        (self.mac / "docs/media.yml").unlink()
        original = self.root / "original.yml"
        original.write_text("original\n")
        (self.mac / "docs/media.yml").symlink_to(original)
        before = self.outputs()
        result = self.run_script("docs-media.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("symlink", result.stderr)
        self.assertEqual(self.outputs(), before)
        self.assertTrue((self.mac / "docs/media.yml").is_symlink())

    def test_override_with_spaces_forwards_source_and_exit_status(self):
        cli = self.cli(self.root / "explicit CLI")
        result = self.run_script("docs-check.sh", BOB_CLI_DIR=str(cli), JUST_EXIT="37")
        self.assertEqual(result.returncode, 37, result.stderr)
        called = json.loads((self.root / "just.json").read_text())
        self.assertEqual(Path(called["cwd"]).resolve(), Path(cli).resolve())
        self.assertEqual(called["args"], ["docs-check"])
        self.assertEqual(Path(called["source"]).resolve(), Path(self.mac).resolve())
        self.assertFalse((self.root / "git.log").exists())

    def test_invalid_overrides_never_fall_through(self):
        self.cli(self.root / "bob-cli")
        incomplete = self.root / "incomplete"
        incomplete.mkdir()
        for value in ("", str(self.root / "missing"), str(incomplete)):
            with self.subTest(value=value):
                result = self.run_script("docs-check.sh", BOB_CLI_DIR=value)
                self.assertEqual(result.returncode, 2)
                self.assertIn("never falls through", result.stderr)
                self.assertFalse((self.root / "just.json").exists())
                self.assertFalse((self.root / "git.log").exists())

    def test_sibling_is_used_without_fetch_or_reset(self):
        sibling = self.cli(self.root / "bob-cli")
        result = self.run_script("docs-check.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            Path(json.loads((self.root / "just.json").read_text())["cwd"]).resolve(),
            Path(sibling).resolve(),
        )
        self.assertFalse((self.root / "git.log").exists())

    def test_managed_cache_clone_refresh_and_wrong_origin(self):
        for _ in range(2):
            result = self.run_script("docs-check.sh")
            self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.root / "git.log").read_text()
        self.assertIn("clone --depth 1 --branch master", log)
        self.assertIn("fetch --depth 1", log)
        self.assertIn("reset --hard " + "b" * 40, log)
        (self.root / "git.log").unlink()
        result = self.run_script("docs-check.sh", GIT_ORIGIN="https://example.invalid/foreign")
        self.assertEqual(result.returncode, 2)
        log = (self.root / "git.log").read_text()
        self.assertNotIn("fetch", log)
        self.assertNotIn("reset", log)


if __name__ == "__main__":
    unittest.main()
