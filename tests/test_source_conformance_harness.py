# SPDX-License-Identifier: Apache-2.0
"""Exercise conformance-runner failures with a real pinned fixture repository."""
import contextlib
import io
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "source/tests/conformance.py"


class SourceConformanceHarnessTests(unittest.TestCase):
    def invoke(self, *, diagnostic=b"", status=0, timeout=False, mutation=None):
        original_run = subprocess.run
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            script = root / "source/tests/conformance.py"
            script.parent.mkdir(parents=True)
            script.write_bytes(SCRIPT.read_bytes())
            cache = root / ".toolchain/toml-test"
            suite = cache / "tests"
            (suite / "valid").mkdir(parents=True)
            (suite / "invalid").mkdir()
            (suite / "valid/one.toml").write_bytes(b"v=1\n")
            (suite / "invalid/one.toml").write_bytes(b"v=[\n")
            for version in ("1.0", "1.1"):
                (suite / ("files-toml-" + version + ".0")).write_text("valid/one.toml\ninvalid/one.toml\n")
            def git(*arguments):
                return subprocess.check_output(["git", "-c", "core.hooksPath=/dev/null", "-c",
                                               "commit.gpgsign=false", "-c", "user.name=Harness test",
                                               "-c", "user.email=harness@example.invalid", *arguments], cwd=cache)
            git("init", "--quiet")
            git("add", "tests")
            git("commit", "--quiet", "-m", "fixture snapshot")
            (root / "TOML_TEST_REVISION").write_bytes(git("rev-parse", "HEAD"))
            if mutation:
                mutation(suite)
            calls = []
            def execute(command, **kwargs):
                if command[0] == "git":
                    return original_run(command, **kwargs)
                calls.append(command)
                if timeout:
                    raise subprocess.TimeoutExpired(command, 10)
                output = b"1\n" if kwargs["input"] in (b"v=1\n", b"v=2\n") else b"0\n"
                return subprocess.CompletedProcess(command, status, output, diagnostic)
            with patch.object(sys, "argv", [str(script), "unused-index"]), \
                    patch("subprocess.run", side_effect=execute), \
                    contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(script), run_name="__main__")
            self.assertEqual(len(calls), 4)

    def test_complete_clean_fixture_run_passes(self):
        self.invoke()

    def test_zero_exit_with_diagnostics_is_not_a_pass(self):
        for diagnostic in (b"runtime error: bounds", b"AddressSanitizer", b"unexpected warning"):
            with self.subTest(diagnostic=diagnostic), self.assertRaises(AssertionError):
                self.invoke(diagnostic=diagnostic)

    def test_incomplete_manifest_is_not_reported_as_complete(self):
        for contents in ("", "valid/one.toml\n"):
            with self.subTest(contents=contents), self.assertRaises(subprocess.CalledProcessError):
                self.invoke(mutation=lambda suite: (suite / "files-toml-1.0.0").write_text(contents))

    def test_modified_fixture_cannot_keep_the_pinned_provenance_claim(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(mutation=lambda suite: (suite / "valid/one.toml").write_bytes(b"v=2\n"))

    def test_crashes_and_timeouts_propagate(self):
        for status in (1, -6):
            with self.subTest(status=status), self.assertRaises(AssertionError):
                self.invoke(status=status)
        with self.assertRaises(subprocess.TimeoutExpired):
            self.invoke(timeout=True)


if __name__ == "__main__":
    unittest.main()
