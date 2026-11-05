# SPDX-License-Identifier: Apache-2.0
"""Fuzz-runner control-plane checks without compiling or executing native code."""
import contextlib
import io
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = (ROOT / "scripts/fuzz.py", ROOT / "source/scripts/fuzz.py")
VALID = b"Done 10 runs in 1 second(s)\n"


class FuzzHarnessTests(unittest.TestCase):
    def invoke(self, script, log=VALID, status=0, timeout=False):
        namespace = runpy.run_path(str(script))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            suite = root / ".toolchain/toml-test/tests"
            (suite / "valid").mkdir(parents=True)
            (suite / "valid/one.toml").write_bytes(b"v=1\n")
            for version in ("1.0", "1.1"):
                (suite / ("files-toml-" + version + ".0")).write_text("valid/one.toml\n")
            (root / "GOOSE_REVISION").write_text("test-pin")
            (root / "TOML_TEST_REVISION").write_text("test-fixtures")
            namespace["main"].__globals__["ROOT"] = root if script == SCRIPTS[0] else source
            security = {"HASH_REVISION": "test-pin", "MAX_INPUT_BYTES": 32, "MAX_NODES": 8,
                        "collision_keys": lambda count: ["key"], "full_collision_keys": lambda count: ["long-key"]}
            campaigns = []
            def execute(command, **kwargs):
                name = Path(command[0]).name
                if name == "self-test":
                    artifact = next(value.split("=", 1)[1] for value in command if value.startswith("-exact_artifact_path="))
                    Path(artifact).write_bytes((Path(command[1]) / "input").read_bytes())
                    kwargs["stdout"].write(b"assert failed\n")
                    return subprocess.CompletedProcess(command, 1)
                if name == "parser-fuzzer":
                    campaigns.append(command)
                    if timeout:
                        raise subprocess.TimeoutExpired(command, 121)
                    kwargs["stdout"].write(log)
                    return subprocess.CompletedProcess(command, status)
                return subprocess.CompletedProcess(command, 0)
            with patch.object(sys, "argv", [str(script), "--goose", "unused", "--seconds", "1", "--runs", "10"]), \
                    patch("subprocess.run", side_effect=execute), \
                    patch("runpy.run_path", return_value=security), \
                    contextlib.redirect_stdout(io.StringIO()):
                namespace["main"]()
            self.assertEqual(len(campaigns), 1)

    def test_normal_completion_passes_for_both_runners(self):
        for script in SCRIPTS:
            with self.subTest(script=script):
                self.invoke(script)

    def test_truncated_malformed_or_ambiguous_summary_is_not_success(self):
        for script in SCRIPTS:
            for log in (b"Done 10\n", b"Done 10 not-a-summary\n", VALID + VALID):
                with self.subTest(script=script, log=log), self.assertRaises(RuntimeError):
                    self.invoke(script, log=log)

    def test_missing_and_zero_execution_summaries_fail(self):
        for script in SCRIPTS:
            for log in (b"", b"Done 0 runs in 1 second(s)\n"):
                with self.subTest(script=script, log=log), self.assertRaises(RuntimeError):
                    self.invoke(script, log=log)

    def test_campaign_crash_and_timeout_propagate(self):
        for script in SCRIPTS:
            for status in (1, -6):
                with self.subTest(script=script, status=status), self.assertRaises(SystemExit):
                    self.invoke(script, status=status)
            with self.subTest(script=script), self.assertRaises(subprocess.TimeoutExpired):
                self.invoke(script, timeout=True)


if __name__ == "__main__":
    unittest.main()
