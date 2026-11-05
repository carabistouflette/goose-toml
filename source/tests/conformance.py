#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check source indexing against pinned official TOML fixture expectations."""
import subprocess
import sys
from pathlib import Path
if not __debug__:
    raise SystemExit('Do not use -O: assertions are required')
binary = str(Path(sys.argv[1]).resolve())
suite = Path(__file__).resolve().parents[2] / '.toolchain/toml-test/tests'
# Check tracked fixture worktree cleanliness against the pinned revision.
# File existence alone permits truncated manifests to report a partial pass.
revision = (Path(__file__).resolve().parents[2] / 'TOML_TEST_REVISION').read_text().strip()
subprocess.run(['git', '-C', str(suite.parent), 'diff', '--quiet', '--no-ext-diff',
                revision, '--', 'tests'], check=True, capture_output=True, timeout=10)
for version in ('1.0', '1.1'):
    manifest = suite / ('files-toml-' + version + '.0')
    if not manifest.is_file():
        raise SystemExit('Pinned fixtures missing; run the root make conformance first')
    count = 0
    for name in manifest.read_text().splitlines():
        if not name.endswith('.toml'):
            continue
        run = subprocess.run([binary, version], input=(suite / name).read_bytes(), capture_output=True, timeout=10)
        assert run.returncode == 0, (version, name, run.returncode, run.stderr[:2000])
        assert not run.stderr, (version, name, "unexpected diagnostics", run.stderr[:2000])
        expected = b'1\n' if name.startswith('valid/') else b'0\n'
        assert run.stdout == expected, (version, name, run.stdout, run.stderr[:2000])
        count += 1
    print(f'TOML {version} source-index equivalence: {count} pinned fixtures passed')
