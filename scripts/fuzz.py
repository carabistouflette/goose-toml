#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build and run a bounded Clang/libFuzzer + ASan/UBSan parser campaign.

Run make setup and make conformance first. Generated code, writable corpus,
logs, and reproducible failure artifacts remain under .build/fuzz/.
"""
import argparse
import hashlib
import json
import runpy
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT / ".toolchain/goose/build/goose")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--runs", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=20261104)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 3600 or not 1 <= args.runs <= 100000000 or not 1 <= args.seed < 2**32:
        parser.error("seconds must be 1..3600, runs 1..100000000, seed 1..4294967295")
    suite = ROOT / ".toolchain/toml-test/tests"
    manifest = suite / "files-toml-1.0.0"
    if not manifest.is_file():
        parser.error("pinned official fixtures are missing; run make conformance first")
    revision = (ROOT / "TOML_TEST_REVISION").read_text().strip()
    work = ROOT / ".build/fuzz"
    seeds = work / ("seeds-" + revision)
    corpus = work / "corpus"
    artifacts = work / "artifacts"
    for directory in (seeds, corpus, artifacts):
        directory.mkdir(parents=True, exist_ok=True)

    def seed(data):
        (seeds / hashlib.sha256(data).hexdigest()).write_bytes(data)

    official = 0
    for name in manifest.read_text().splitlines():
        if name.endswith(".toml"):
            seed((suite / name).read_bytes())
            official += 1
    # Add limit/error paths and genuine hash collisions that ordinary mutations
    # would be unlikely to construct. Reuse the pinned-hash security generator.
    security = runpy.run_path(str(ROOT / "scripts/security-test.py"))
    if (ROOT / "GOOSE_REVISION").read_text().strip() != security["HASH_REVISION"]:
        parser.error("collision generator must be revalidated for the compiler pin")
    keys = security["collision_keys"](5000)
    lines = [(json.dumps(key) + "=1\n").encode("ascii") for key in keys]
    seed(b"".join(lines[:200]))
    seed(b"".join(lines))
    full_keys = security["full_collision_keys"](500)
    full_lines = [(json.dumps(key) + f"={i}\n").encode("ascii") for i, key in enumerate(full_keys)]
    seed(b"".join(full_lines[:100]))
    seed(b"".join(full_lines))
    limit = security["MAX_INPUT_BYTES"]
    nodes = security["MAX_NODES"]
    seed(b"v='" + b"x" * (limit - 4) + b"'")
    seed(b" " * (limit + 1))
    seed(b"v=[" + b"1," * (nodes - 2) + b"]")
    seed(b"v=" + b"{a=" * 62 + b"[" + b"1," * 64001 + b"]" + b"}" * 62)

    goose = str(args.goose.resolve())
    subprocess.run([goose, "tests/fuzz.goose", "--standalone", "--debug", "--no-bce",
                    "--header", str(work / "parser-fuzz.h"), "-o", str(work / "parser-fuzz.c")],
                   cwd=ROOT, check=True)
    instrument = ["-O1", "-g", "-fsanitize=fuzzer-no-link,address,undefined",
                  "-fno-sanitize-recover=all", "-fno-omit-frame-pointer"]
    subprocess.run([args.cc, *instrument, "-D_Exit=goose_fuzz_exit", "-c",
                    str(work / "parser-fuzz.c"), "-o", str(work / "parser-fuzz.o")],
                   cwd=ROOT, check=True)
    link = [args.cc, "-O1", "-g", "-fsanitize=fuzzer,address,undefined",
            "-fno-sanitize-recover=all", "-fno-omit-frame-pointer",
            str(work / "parser-fuzz.o"), "tests/fuzz.c", "-I" + str(work),
            "-lm", "-ldl", "-lpthread"]
    subprocess.run([*link, "-o", str(work / "parser-fuzzer")], cwd=ROOT, check=True)
    subprocess.run([*link, "-DGOOSE_FUZZ_SELF_TEST=1", "-o", str(work / "self-test")],
                   cwd=ROOT, check=True)
    # Verify the central failure path, not just sanitizers: Goose aborts must
    # become a libFuzzer crash with the exact bytes retained for reproduction.
    probe = work / "self-test-seeds"
    probe.mkdir(exist_ok=True)
    expected = b"libFuzzer Goose assertion bridge probe"
    (probe / "input").write_bytes(expected)
    crash = work / "self-test-crash"
    crash.unlink(missing_ok=True)
    with (work / "self-test.log").open("wb") as log:
        smoke = subprocess.run([str(work / "self-test"), str(probe), "-runs=10", "-seed=1",
                                "-exact_artifact_path=" + str(crash)],
                               cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=30)
    smoke_log = (work / "self-test.log").read_text(errors="replace")
    if smoke.returncode == 0 or not crash.is_file() or crash.read_bytes() != expected or "assert failed" not in smoke_log:
        raise RuntimeError("Goose assertion artifact self-test failed; see " + str(work / "self-test.log"))
    print("Verified Goose assertion failures save the exact triggering input", flush=True)
    command = [str(work / "parser-fuzzer"), str(corpus), str(seeds),
               "-max_len=" + str(limit + 1), "-max_total_time=" + str(args.seconds),
               "-runs=" + str(args.runs), "-seed=" + str(args.seed), "-timeout=5",
               "-rss_limit_mb=1024", "-artifact_prefix=" + str(artifacts) + "/"]
    print(f"Fuzzing with {official} official fixtures and resource/collision seeds", flush=True)
    print("Campaign log: " + str(work / "run.log"), flush=True)
    with (work / "run.log").open("wb") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                timeout=args.seconds + 120)
    if result.returncode:
        print((work / "run.log").read_text(errors="replace")[-12000:])
        raise SystemExit(result.returncode if result.returncode > 0 else 1)
    summary = (work / "run.log").read_text(errors="replace").splitlines()
    completed = [line for line in summary if line.startswith("Done ")]
    if not completed or int(completed[-1].split()[1]) < 1:
        raise RuntimeError("libFuzzer exited without an execution summary; see " + str(work / "run.log"))
    for line in summary:
        if line.startswith("Done ") or "DONE" in line:
            print(line)


if __name__ == "__main__":
    main()
