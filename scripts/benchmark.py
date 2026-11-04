#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Measure one binary, or alternate two binaries, retaining raw samples/medians.

For a comparison, both binaries need the same workloads and compiler flags.
This is a warm destination-reuse throughput benchmark, not an allocation count
or a cold-parse latency measurement. No machine-independent speed claim is made.
"""
import argparse
import hashlib
import json
import os
import platform
import random
import re
import statistics
import subprocess
from pathlib import Path

LINE = re.compile(r"(.+): (\d+) parses, (\d+) bytes/input, (\d+) ns, checksum (\d+)")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--iterations", type=int, default=100000)
    parser.add_argument("--repeats", type=int, default=9)
    parser.add_argument("--output", type=Path, default=Path(".build/benchmark.json"))
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000 or not 3 <= args.repeats <= 99:
        parser.error("iterations must be 1..1000000 and repeats 3..99")
    cpu = None
    if hasattr(os, "sched_getaffinity"):
        cpu = min(os.sched_getaffinity(0))
        os.sched_setaffinity(0, {cpu})
    binaries = {"candidate": args.candidate.resolve()}
    if args.baseline is not None:
        binaries = {"baseline": args.baseline.resolve(), **binaries}
    samples = {name: {} for name in binaries}
    metadata = {}

    def run(name, record):
        result = subprocess.run([str(binaries[name]), str(args.iterations)],
                                check=True, capture_output=True, text=True, timeout=120)
        rows = []
        for line in result.stdout.splitlines():
            match = LINE.fullmatch(line)
            if match is None:
                raise ValueError(f"invalid benchmark output: {line!r}")
            workload, count, size, elapsed, checksum = match.groups()
            count, size, elapsed, checksum = map(int, (count, size, elapsed, checksum))
            if count <= 0 or elapsed <= 0:
                raise ValueError("benchmark counters must be positive")
            definition = {"iterations": count, "input_bytes": size, "checksum": checksum}
            if workload in metadata and metadata[workload] != definition:
                raise ValueError("workloads differ")
            metadata[workload] = definition
            rows.append(workload)
            if record:
                samples[name].setdefault(workload, []).append(elapsed / count)
        if not rows or len(set(rows)) != len(rows):
            raise ValueError("empty or duplicated benchmark workloads")
        return set(rows)

    # Warm each executable before measuring. With two binaries, alternate order
    # per paired repetition to reduce drift; keep raw samples in either mode.
    expected_workloads = None
    for name in binaries:
        measured = run(name, False)
        if expected_workloads is not None and measured != expected_workloads:
            raise ValueError("workload sets differ")
        expected_workloads = measured
    rng = random.Random(0xB3AC4)
    for _ in range(args.repeats):
        order = list(binaries)
        rng.shuffle(order)
        for name in order:
            measured = run(name, True)
            if measured != expected_workloads:
                raise ValueError("workload sets differ")
    workloads = {}
    for workload, definition in metadata.items():
        if any(len(samples[name][workload]) != args.repeats for name in binaries):
            raise ValueError("incomplete benchmark samples")
        medians = {name: statistics.median(samples[name][workload]) for name in binaries}
        workloads[workload] = {**definition,
                              "candidate_ns_per_parse": medians["candidate"],
                              "samples_ns_per_parse": {name: samples[name][workload] for name in binaries}}
        if "baseline" in medians:
            workloads[workload]["baseline_ns_per_parse"] = medians["baseline"]
            workloads[workload]["speedup"] = medians["baseline"] / medians["candidate"]
    report = {"platform": platform.platform(), "cpu_affinity": cpu,
              "repeats": args.repeats, "binaries": {k: str(v) for k, v in binaries.items()},
              "binary_sha256": {k: hashlib.sha256(v.read_bytes()).hexdigest() for k, v in binaries.items()},
              "workloads": workloads}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Recorded {args.repeats} measurement rounds in {args.output}")


if __name__ == "__main__":
    main()
