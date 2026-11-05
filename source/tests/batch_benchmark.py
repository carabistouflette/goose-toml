#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Alternating full-operation batch versus sequential public-API measurements."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
INPUTS = ['source/editor.goose', 'toml.goose', 'document.goose', 'writer.goose',
          'vendor/text.goose', 'GOOSE_REVISION', 'source/tests/batch_bench.goose',
          'source/tests/batch_benchmark.py']
CASES = [('single_control', 8, 1, 5000), ('small_4', 8, 4, 2000),
         ('wide_16', 1024, 16, 100), ('wide_64', 1024, 64, 30)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--goose', required=True, type=Path)
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--cpu', required=True, type=int)
    parser.add_argument('--rounds', type=int, default=7)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not __debug__:
        parser.error('assertions required; do not use -O')
    if not 3 <= args.rounds <= 31 or args.cpu not in os.sched_getaffinity(0):
        parser.error('rounds must be 3..31 and CPU available')
    os.sched_setaffinity(0, {args.cpu})
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    git = lambda *argv: subprocess.check_output(['git', *argv], cwd=ROOT, text=True).strip()
    snapshot = lambda: {'head': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}'),
                         'status': git('status', '--porcelain'),
                         'sha256': {name: digest(ROOT / name) for name in INPUTS}}
    before = snapshot()
    if before['status']:
        parser.error('commit sources before measuring')
    goose = args.goose.resolve()
    compiler_hash = digest(goose)
    binary = ROOT / 'source/.build/batch-bench-measured'
    binary.parent.mkdir(exist_ok=True)
    subprocess.run([str(goose), 'build', 'source/tests/batch_bench.goose', '--cc', args.cc,
                    '-O2', '-o', str(binary)], cwd=ROOT, check=True)
    binary_hash = digest(binary)
    report = {'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'provenance': before, 'compiler_sha256': compiler_hash, 'binary_sha256': binary_hash,
              'goose': subprocess.check_output([str(goose), '--version'], text=True).strip(),
              'cc': subprocess.check_output([args.cc, '--version'], text=True).splitlines()[0],
              'platform': platform.platform(), 'cpu': args.cpu, 'rounds': args.rounds,
              'cpu_model': next((s.split(':', 1)[1].strip() for s in Path('/proc/cpuinfo').read_text().splitlines()
                                 if s.startswith('model name')), ''),
              'flags': '-O2', 'cases': CASES, 'samples': [],
              'scope': 'Shared host; no exclusive CPU/host claim. Prebuilt independent existing root leaves, alternating put/remove. Sequential calls transfer each owned result through clear/append before the next call. Batch and sequence produce identical exact bytes. No insertion/dependency/general speed claim.',
              'checks': 'Full expected bytes before/after timing; one selected warmup in each process; timed loops check error/length and length+endpoint checksum (not full-byte hashing).'}
    lengths = {}
    for round_id in range(args.rounds):
        for case_id, (name, nodes, count, iterations) in enumerate(CASES):
            modes = ['batch', 'sequence'] if (round_id + case_id) % 2 == 0 else ['sequence', 'batch']
            for mode in modes:
                raw = subprocess.check_output([str(binary), mode, str(nodes), str(count), str(iterations)],
                                              text=True, timeout=120)
                fields = raw.strip().split('\t')
                assert len(fields) == 6 and fields[0] == mode
                ns, actual_iterations, source_bytes, output_bytes, checksum = map(int, fields[1:])
                assert ns > 0 and actual_iterations == iterations and source_bytes > 0 and output_bytes > 0
                assert checksum == iterations * (output_bytes + ord('#') + ord('\n'))
                pair = source_bytes, output_bytes
                assert name not in lengths or lengths[name] == pair
                lengths[name] = pair
                report['samples'].append({'round': round_id, 'case': name, 'mode': mode, 'ns': ns,
                                          'iterations': iterations, 'source_bytes': source_bytes,
                                          'output_bytes': output_bytes, 'checksum': checksum})
    report['median_ns_per_batch'] = {name: {mode: statistics.median(row['ns'] / row['iterations']
                                       for row in report['samples'] if row['case'] == name and row['mode'] == mode)
                                       for mode in ['batch', 'sequence']} for name, *_ in CASES}
    report['batch_over_sequence'] = {name: row['batch'] / row['sequence']
                                    for name, row in report['median_ns_per_batch'].items()}
    assert snapshot() == before and digest(goose) == compiler_hash and digest(binary) == binary_hash
    report['completed_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['batch_over_sequence'], indent=2))


if __name__ == '__main__':
    main()
