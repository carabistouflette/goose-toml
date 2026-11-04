#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Paired complete default-operation timings from two clean standalone clones."""
import argparse
import hashlib
import json
import os
import platform
import statistics
import subprocess
import time
from pathlib import Path

SOURCES = ['source/bench.goose', 'source/editor.goose', 'toml.goose',
           'document.goose', 'writer.goose', 'vendor/text.goose', 'GOOSE_REVISION']
CASES = ['put_small', 'remove_small', 'put_large', 'remove_large']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--goose', required=True, type=Path)
    parser.add_argument('--cc', default='gcc')
    parser.add_argument('--cpu', required=True, type=int)
    parser.add_argument('--rounds', type=int, default=9)
    parser.add_argument('--iterations', type=int, default=1000)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if not 1 <= args.rounds <= 99 or not 1 <= args.iterations <= 100000:
        parser.error('rounds must be 1..99 and iterations 1..100000')
    if args.cpu not in os.sched_getaffinity(0):
        parser.error('CPU is unavailable in this process affinity')
    os.sched_setaffinity(0, {args.cpu})
    paths = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    goose = args.goose.resolve()
    stamp = lambda: time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    git = lambda path, *options: subprocess.check_output(['git', '-C', str(path), *options], text=True).strip()
    snapshot = lambda path: {'sha': git(path, 'rev-parse', 'HEAD'),
                             'dirty': git(path, 'status', '--porcelain'),
                             'source_sha256': {name: digest(path / name) for name in SOURCES}}
    report = {'started_utc': stamp(), 'platform': platform.platform(), 'cpu': args.cpu,
              'cpu_model': next((s.split(':', 1)[1].strip() for s in Path('/proc/cpuinfo').read_text().splitlines()
                                 if s.startswith('model name')), ''),
              'rounds': args.rounds, 'iterations': args.iterations, 'warmup_processes_per_build': 1,
              'flags': 'goose build source/bench.goose --cc CC -O2',
              'cc': subprocess.check_output([args.cc, '--version'], text=True).splitlines()[0],
              'compiler_sha256': digest(goose),
              'goose_version': subprocess.check_output([str(goose), '--version'], text=True).strip(),
              'measurement_script_sha256': digest(Path(__file__)),
              'goose_revision': (paths['candidate'] / 'GOOSE_REVISION').read_text().strip(),
              'builds': {}, 'samples': [],
              'scope': 'Complete fresh owned edits on a shared host; alternating process order; no exclusive isolation claim.'}
    for name, path in paths.items():
        before = snapshot(path)
        if before['dirty']:
            parser.error(f'{name} checkout is dirty')
        binary = path / 'source/.build/profile-bench'
        binary.parent.mkdir(exist_ok=True)
        subprocess.run([str(goose), 'build', 'source/bench.goose', '--cc', args.cc, '-O2', '-o', str(binary)],
                       cwd=path, check=True)
        assert snapshot(path) == before, 'sources changed during build'
        report['builds'][name] = {**before, 'binary_sha256': digest(binary)}
    assert report['builds']['baseline']['source_sha256']['source/bench.goose'] == report['builds']['candidate']['source_sha256']['source/bench.goose']
    assert report['builds']['baseline']['source_sha256']['GOOSE_REVISION'] == report['builds']['candidate']['source_sha256']['GOOSE_REVISION']

    lengths = {}

    def sample(name):
        binary = paths[name] / 'source/.build/profile-bench'
        output = subprocess.check_output([str(binary), str(args.iterations)], text=True, timeout=120)
        rows = [line.split('\t') for line in output.splitlines()]
        assert [row[0] for row in rows] == CASES + ['checksum']
        assert all(int(row[2]) == args.iterations and int(row[1]) >= 0 for row in rows[:-1])
        assert int(rows[-1][1]) == sum(int(row[2]) * int(row[4]) for row in rows[:-1])
        for row in rows[:-1]:
            current = int(row[3]), int(row[4])
            assert row[0] not in lengths or lengths[row[0]] == current, 'fixture lengths changed'
            lengths[row[0]] = current
        return {row[0]: {'ns': int(row[1]), 'input_bytes': int(row[3]), 'output_bytes': int(row[4])}
                for row in rows[:-1]}

    for name in paths:
        sample(name)
    for round_id in range(args.rounds):
        order = list(paths) if round_id % 2 == 0 else list(reversed(paths))
        for name in order:
            report['samples'].append({'round': round_id, 'build': name, 'cases': sample(name)})
    report['median_ns_per_op'] = {name: {case: statistics.median(row['cases'][case]['ns'] for row in report['samples']
                                                               if row['build'] == name) / args.iterations
                                         for case in CASES} for name in paths}
    report['candidate_over_baseline'] = {case: report['median_ns_per_op']['candidate'][case] /
                                        report['median_ns_per_op']['baseline'][case] for case in CASES}
    report['completed_utc'] = stamp()
    for name, path in paths.items():
        assert snapshot(path) == {key: report['builds'][name][key] for key in ('sha', 'dirty', 'source_sha256')}
        assert digest(path / 'source/.build/profile-bench') == report['builds'][name]['binary_sha256']
    assert digest(goose) == report['compiler_sha256'], 'compiler changed during measurement'
    args.output.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['candidate_over_baseline'], indent=2))


if __name__ == '__main__':
    if not __debug__:
        raise SystemExit('Do not use -O: assertions are required')
    main()
