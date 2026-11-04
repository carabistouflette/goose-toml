#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Warm complete edits: source parsing, copying and output validation included."""
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
from pathlib import Path
if not __debug__:
    raise SystemExit('Do not use -O: assertions are required')
root = Path(__file__).resolve().parents[2]
source_paths = ['source/editor.goose', 'source/bench.goose', 'toml.goose',
                'document.goose', 'writer.goose', 'vendor/text.goose']
def fingerprints():
    return {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in source_paths}
snapshot_path = Path('.build/benchmark-source.json')
if sys.argv[1:] == ['--snapshot']:
    snapshot_path.write_text(json.dumps({
        'source_sha256': fingerprints(),
        'base_revision': subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip(),
        'dirty': bool(subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()),
    }, indent=2) + '\n')
    raise SystemExit(0)
snapshot = json.loads(snapshot_path.read_text())
assert fingerprints() == snapshot['source_sha256'], 'source changed during benchmark build'
binary = str(Path(sys.argv[1]).resolve())
iterations = int(sys.argv[2])
if not 1 <= iterations <= 100000:
    raise SystemExit('iterations must be 1..100000')
cpu = None
if hasattr(os, 'sched_getaffinity'):
    cpu = min(os.sched_getaffinity(0)); os.sched_setaffinity(0, {cpu})
fixtures = ['put_small', 'remove_small', 'put_large', 'remove_large']
samples = {name: [] for name in fixtures}
lengths = {}
for index in range(8):
    run = subprocess.run([binary, str(iterations)], capture_output=True, text=True, check=True, timeout=120)
    rows = [line.split('\t') for line in run.stdout.splitlines()]
    assert [r[0] for r in rows] == fixtures + ['checksum'], run.stdout
    checksum = 0
    for name, elapsed, count, size, output in rows[:-1]:
        assert int(elapsed) >= 0 and int(count) == iterations
        current = {'input': int(size), 'output': int(output)}
        if name in lengths:
            assert lengths[name] == current
        lengths[name] = current; checksum += int(output) * iterations
        if index:
            samples[name].append(int(elapsed))
    assert int(rows[-1][1]) == checksum
cpuinfo = Path('/proc/cpuinfo')
model = next((line.split(':', 1)[1].strip() for line in cpuinfo.read_text().splitlines()
              if line.startswith('model name')), '') if cpuinfo.exists() else platform.processor()
report = {
    'platform': platform.platform(), 'affinity_cpu': cpu, 'iterations': iterations,
    'cpu': model, 'warmup_processes': 1, 'raw_ns': samples,
    'median_ns_per_operation': {name: statistics.median(values) / iterations for name, values in samples.items()},
    'lengths': lengths, 'goose_revision': (root / 'GOOSE_REVISION').read_text().strip(),
    'cc_version': subprocess.check_output([os.environ.get('BENCH_CC', 'gcc'), '--version'], text=True).splitlines()[0],
    'flags': 'goose build -O2', 'binary_sha256': hashlib.sha256(Path(binary).read_bytes()).hexdigest(),
    'base_revision': snapshot['base_revision'], 'dirty': snapshot['dirty'],
    'source_sha256': snapshot['source_sha256'],
    'scope': 'Warm complete edits with fresh private parser state and owned output; shared machine; no universal ranking.',
}
assert fingerprints() == snapshot['source_sha256'], 'source changed during benchmark run'
Path('.build/benchmark.json').write_text(json.dumps(report, indent=2) + '\n')
for name, value in report['median_ns_per_operation'].items():
    print(f'{name}: {value:.1f} ns/op')
print('Raw samples and provenance: .build/benchmark.json')
