#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Build and run a bounded Clang/libFuzzer + ASan/UBSan source-editor campaign.

Run make setup first. Generated code, writable corpus,
logs, and reproducible failure artifacts remain under .build/fuzz/.
"""
import argparse
import hashlib
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--goose", type=Path, default=ROOT.parent / ".toolchain/goose/build/goose")
    parser.add_argument("--cc", default="clang")
    parser.add_argument("--seconds", type=int, default=30)
    parser.add_argument("--runs", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=20261104)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 3600 or not 1 <= args.runs <= 100000000 or not 1 <= args.seed < 2**32:
        parser.error("seconds must be 1..3600, runs 1..100000000, seed 1..4294967295")
    work = ROOT / ".build/fuzz"
    seeds = work / "seeds"
    corpus = work / "corpus"
    artifacts = work / "artifacts"
    for directory in (seeds, corpus, artifacts):
        directory.mkdir(parents=True, exist_ok=True)
    suite = ROOT.parent / ".toolchain/toml-test/tests"
    manifest = suite / "files-toml-1.0.0"
    if not manifest.is_file():
        parser.error("pinned fixtures missing; run root make conformance first")
    samples = [b"", b"[dependencies]\nhelper={path='lib'}\n", b"a.b=1\n", b"a={b=1}\n",
               b"#" + b"x" * 1048575, b"#" + b"x" * 1048576]
    for data in samples:
        (seeds / hashlib.sha256(data).hexdigest()).write_bytes(data)
    for name in manifest.read_text().splitlines():
        if name.endswith(".toml"):
            data = (suite / name).read_bytes()
            (seeds / hashlib.sha256(data).hexdigest()).write_bytes(data)
    limit = 1048577
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
               "-max_len=" + str(limit), "-max_total_time=" + str(args.seconds),
               "-runs=" + str(args.runs), "-seed=" + str(args.seed), "-timeout=5",
               "-rss_limit_mb=1024", "-artifact_prefix=" + str(artifacts) + "/"]
    print("Fuzzing source-index, no-op preservation and parsed source edits", flush=True)
    print("Campaign log: " + str(work / "run.log"), flush=True)
    with (work / "run.log").open("wb") as log:
        result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                timeout=args.seconds + 120)
    if result.returncode:
        print((work / "run.log").read_text(errors="replace")[-12000:])
        raise SystemExit(result.returncode if result.returncode > 0 else 1)
    summary = (work / "run.log").read_text(errors="replace").splitlines()
    completed = [re.fullmatch(r"Done ([0-9]+) runs in [0-9]+ second\(s\)", line)
                 for line in summary if line.startswith("Done ")]
    if len(completed) != 1 or completed[0] is None or int(completed[0].group(1)) < 1:
        raise RuntimeError("libFuzzer exited without one complete, positive execution summary; see " + str(work / "run.log"))
    for line in summary:
        if line.startswith("Done ") or "DONE" in line:
            print(line)


if __name__ == "__main__":
    main()
