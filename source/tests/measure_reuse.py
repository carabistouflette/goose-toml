#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Calibrate then measure immutable source-editor snapshots on a shared Linux host."""
import argparse
import hashlib
import json
import os
import platform
import random
import statistics
import subprocess
import time
from pathlib import Path

FILES = ['source/editor.goose', 'source/tests/profile_costs.goose', 'toml.goose',
         'document.goose', 'writer.goose', 'vendor/text.goose', 'GOOSE_REVISION']
# No Cartesian product: large commentary + wide documents can exceed 1 MiB.
SHAPES = [('remove', 0, n, target) for n in (1, 8, 32) for target in sorted({0, n - 1})]
SHAPES += [(op, pad, 1, 0) for pad in (65536, 1000000) for op in ('set', 'remove')]
SHAPES += [(op, 0, 10000, target) for target in (0, 9999) for op in ('set', 'remove')]
SHAPES += [('remove', 0, 1, -1), ('remove', 1000000, 1, -1),
           ('remove', 0, 10000, -1), ('set', 0, 8, -1), ('set', 0, 1, 0)]
CASES = [(profile, *shape) for profile in ('source', 'legacy') for shape in SHAPES]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def snapshot(root):
    return {'sha': git(root, 'rev-parse', 'HEAD'), 'dirty': git(root, 'status', '--porcelain'),
            'hashes': {name: digest(root / name) for name in FILES}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--goose', type=Path, required=True)
    parser.add_argument('--cpu', type=int, required=True)
    parser.add_argument('--calibrate', action='store_true')
    parser.add_argument('--config', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--rounds', type=int, default=9)
    args = parser.parse_args()
    if args.cpu not in os.sched_getaffinity(0) or not 1 <= args.rounds <= 99:
        parser.error('invalid CPU or rounds')
    if not args.calibrate and args.output is None:
        parser.error('--output required for measurement')
    os.sched_setaffinity(0, {args.cpu})
    roots = {'baseline': args.baseline.resolve(), 'candidate': args.candidate.resolve()}
    before = {name: snapshot(root) for name, root in roots.items()}
    if any(item['dirty'] for item in before.values()):
        parser.error('snapshots must be clean')
    for name in FILES[1:]:
        if before['baseline']['hashes'][name] != before['candidate']['hashes'][name]:
            parser.error(f'non-engine measurement input differs: {name}')
    compiler = args.goose.resolve()
    report = {'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
              'platform': platform.platform(), 'cpu': args.cpu, 'rounds': args.rounds,
              'seed': 20261104, 'additional_warmups': 8,
              'unchanged_binary_control': roots['baseline'] == roots['candidate'],
              'cpu_model': next(s.split(':', 1)[1].strip() for s in Path('/proc/cpuinfo').read_text().splitlines()
                                if s.startswith('model name')),
              'goose_version': subprocess.check_output([str(compiler), '--version'], text=True).strip(),
              'compiler_sha256': digest(compiler), 'script_sha256': digest(Path(__file__)),
              'goose_revision': (roots['baseline'] / 'GOOSE_REVISION').read_text().strip(),
              'cc': subprocess.check_output(['gcc', '--version'], text=True).splitlines()[0],
              'flags': 'goose build source/tests/profile_costs.goose --cc gcc -O2',
              'snapshots': before, 'samples': [],
              'scope': 'Post-preflight calls, shared host, no exclusive isolation; input construction and exact-byte pre/post checks outside timer.'}
    binaries = {}
    for name, root in roots.items():
        binary = root / '.build/reuse-costs'
        binary.parent.mkdir(exist_ok=True)
        subprocess.run([str(compiler), 'build', 'source/tests/profile_costs.goose', '--cc', 'gcc', '-O2', '-o', str(binary)],
                       cwd=root, check=True)
        binaries[name] = binary
    report['binary_sha256'] = {name: digest(binary) for name, binary in binaries.items()}
    dimensions = {}

    def run(name, case, count):
        argv = [str(binaries[name]), *map(str, case), str(count), '8']
        result = subprocess.run(argv, text=True, capture_output=True, timeout=120, check=True)
        if result.stderr:
            raise AssertionError(result.stderr)
        fields = result.stdout.strip().split('\t')
        assert len(fields) == 11 and fields[:5] == list(map(str, case))
        assert int(fields[5]) == count and int(fields[6]) == 8
        sizes = tuple(map(int, fields[7:9]))
        key = tuple(case)
        assert key not in dimensions or dimensions[key] == sizes
        dimensions[key] = sizes
        elapsed, checksum = map(int, fields[9:])
        assert elapsed > 0 and checksum > 0 and checksum % count == 0
        return {'ns': elapsed, 'iterations': count, 'input_bytes': sizes[0],
                'output_bytes': sizes[1], 'checksum': checksum}

    if args.calibrate:
        calibration = []
        for case in CASES:
            count = 1 if case[2] >= 65536 or case[3] >= 1000 else 1000
            while True:
                samples = {name: run(name, case, count) for name in roots}
                calibration.append({'case': case, 'iterations': count, 'samples': samples})
                if min(row['ns'] for row in samples.values()) >= 10000000 or count == 10000:
                    break
                count = min(count * 2, 10000)
        frozen = []
        for case in CASES:
            selected = next(row for row in reversed(calibration) if tuple(row['case']) == case)
            frozen.append({'case': case, 'iterations': selected['iterations'],
                           'minimum_met': min(row['ns'] for row in selected['samples'].values()) >= 10000000})
        report['calibration_samples'] = calibration
        report['cases'] = frozen
        report['minimum_batch_ns'] = 10000000
    else:
        config = json.loads(args.config.read_text())
        assert [tuple(row['case']) for row in config['cases']] == CASES
        assert config['script_sha256'] == report['script_sha256']
        assert before['baseline'] == config['snapshots']['baseline']
        expected = config['snapshots']['baseline'] if report['unchanged_binary_control'] else config['snapshots']['candidate']
        assert before['candidate'] == expected, 'snapshot differs from frozen calibration'
        for name in FILES[1:]:
            assert config['snapshots']['baseline']['hashes'][name] == before['baseline']['hashes'][name]
        report['config_sha256'] = digest(args.config)
        report['cases'] = config['cases']
        rng = random.Random(20261104)
        for round_id in range(args.rounds):
            order = list(config['cases']); rng.shuffle(order)
            for case_id, item in enumerate(order):
                case = tuple(item['case']); count = item['iterations']
                assert isinstance(count, int) and 1 <= count <= 10000
                for name in (list(roots) if (round_id + case_id) % 2 == 0 else list(reversed(roots))):
                    report['samples'].append({'round': round_id, 'runner': name, 'case': case, **run(name, case, count)})
        report['ratios_of_medians'] = []
        for item in config['cases']:
            case = tuple(item['case'])
            medians = {name: statistics.median(row['ns'] / row['iterations'] for row in report['samples']
                                              if row['runner'] == name and tuple(row['case']) == case) for name in roots}
            report['ratios_of_medians'].append({'case': case, 'ns_per_op': medians,
                                                'candidate_over_baseline': medians['candidate'] / medians['baseline']})
    assert {name: snapshot(root) for name, root in roots.items()} == before
    assert {name: digest(binary) for name, binary in binaries.items()} == report['binary_sha256']
    assert digest(compiler) == report['compiler_sha256']
    report['completed_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    destination = args.config if args.calibrate else args.output
    destination.write_text(json.dumps(report, indent=2) + '\n')
    print(destination)


if __name__ == '__main__':
    if not __debug__:
        raise SystemExit('Do not use -O: assertions required')
    main()
