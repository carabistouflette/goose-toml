#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Pinned fresh owned DOM parsing and writing comparisons; see bench/compare/README.md."""
import argparse
import functools
import hashlib
import json
import math
import os
import platform
import random
import shlex
import statistics
import subprocess
import sys
import time
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / ".build/compare"
ADAPTERS = ROOT / "bench/compare"
PIN = "30172438cee64926dc41fdd9c11fb3ba5b2ba9de"
RUST_PIN = "1.2.0+spec-1.1.0"
NAMES = ("goose", "rust", "go", "cpp")
STATS = ("nodes", "tables", "arrays", "strings", "integers", "floats", "booleans",
         "key_utf8_bytes", "string_utf8_bytes", "integer_sum", "float_times_1000_sum", "true_count")
CARGO_OVERRIDES = {
    "CARGO_ENCODED_RUSTFLAGS": "", "CARGO_PROFILE_RELEASE_LTO": "false",
    "CARGO_PROFILE_RELEASE_OPT_LEVEL": "3", "CARGO_PROFILE_RELEASE_CODEGEN_UNITS": "16",
    "CARGO_PROFILE_RELEASE_DEBUG": "false", "CARGO_PROFILE_RELEASE_DEBUG_ASSERTIONS": "false",
    "CARGO_PROFILE_RELEASE_OVERFLOW_CHECKS": "false", "CARGO_PROFILE_RELEASE_INCREMENTAL": "false",
    "CARGO_PROFILE_RELEASE_PANIC": "unwind", "CARGO_PROFILE_RELEASE_STRIP": "none",
    "CARGO_PROFILE_RELEASE_SPLIT_DEBUGINFO": "off", "CARGO_INCREMENTAL": "0",
    "RUSTC_WRAPPER": "", "RUSTC_WORKSPACE_WRAPPER": "", "RUSTC": "rustc",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fingerprint(data):
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & ((1 << 64) - 1)
    return str(value)


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def strict_json(text):
    def unique_pairs(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate key in runner JSON response: " + key)
            result[key] = value
        return result
    def finite_float(value):
        parsed = float(value)
        if not math.isfinite(parsed):
            raise ValueError("nonfinite JSON number")
        return parsed
    return json.loads(text, object_pairs_hook=unique_pairs,
                      parse_float=finite_float,
                      parse_constant=lambda value: (_ for _ in ()).throw(ValueError("nonfinite JSON value " + value)))


def repository_snapshot():
    return {
        "head": run(["git", "rev-parse", "HEAD"]).stdout.strip(),
        "library_status": run(["git", "status", "--porcelain", "--untracked-files=all", "--", "."]).stdout.splitlines(),
        "tracked_library_diff_sha256": hashlib.sha256(
            run(["git", "diff", "--binary", "HEAD", "--", "."]).stdout.encode()).hexdigest(),
    }


def run(command, *, cwd=ROOT, env=None, timeout=180):
    return subprocess.run([str(part) for part in command], cwd=cwd, env=env,
                          check=True, text=True, capture_output=True, timeout=timeout)


def fresh_env():
    env = os.environ.copy()
    # Avoid hidden optimization flags or disabling the Go GC. Preserve ordinary
    # toolchain discovery, proxies and language caches; record selected versions.
    for key in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "CARGO_PROFILE_RELEASE_OPT_LEVEL",
                "CARGO_PROFILE_RELEASE_LTO", "CARGO_PROFILE_RELEASE_CODEGEN_UNITS",
                "GOFLAGS", "GOGC", "GOMEMLIMIT", "GODEBUG", "GOEXPERIMENT"):
        env.pop(key, None)
    for key in list(env):
        if key.startswith("CARGO_PROFILE_RELEASE_"):
            env.pop(key)
    # Empty encoded flags take precedence over target/build rustflags in Cargo
    # config; merely deleting environment variables would leave those active.
    env.update(CARGO_OVERRIDES)
    env["CARGO_BUILD_TARGET"] = rust_target()
    env["CARGO_TARGET_" + rust_target().upper().replace("-", "_") + "_LINKER"] = "cc"
    return env


@functools.lru_cache(maxsize=1)
def rust_target():
    version = run(["rustc", "-vV"]).stdout
    return next(line.removeprefix("host: ") for line in version.splitlines() if line.startswith("host: "))


def binary_paths():
    return {"goose": BUILD / "goose-runner", "rust": BUILD / "rust" / rust_target() / "release/goose-toml-compare",
            "go": BUILD / "go-runner", "cpp": BUILD / "cpp-runner"}


def verify_rust_commands(log):
    commands = []
    for line in log.splitlines():
        if "Running `" not in line or "--crate-name goose_toml_compare " not in line:
            continue
        words = shlex.split(line.split("Running `", 1)[1].rsplit("`", 1)[0])
        position = words.index("--crate-name")
        preceding = words[:position - 1]
        if (Path(words[position - 1]).name != "rustc" or
                any("=" not in word or not word.split("=", 1)[0].isidentifier() for word in preceding)):
            raise ValueError("effective Rust command uses an unexpected compiler wrapper")
        codegen = []
        for index, word in enumerate(words):
            if word == "-C":
                codegen.append(words[index + 1])
            elif word.startswith("-C"):
                codegen.append(word[2:])
        settings = dict(option.split("=", 1) if "=" in option else (option, "") for option in codegen)
        if (settings.get("opt-level") != "3" or settings.get("codegen-units") != "16"
                or settings.get("lto", "off") not in ("off", "no", "false")
                or settings.get("debuginfo", "0") != "0" or "incremental" in settings
                or any(key.startswith("target-") or key.startswith("link-arg") for key in settings)
                or settings.get("linker") != "cc"
                or "--target" not in words or words[words.index("--target") + 1] != rust_target()):
            raise ValueError("effective Rust compiler options differ from the standard release policy")
        commands.append({"crate": "goose_toml_compare", "target": rust_target(),
                         "codegen_options": [option for option in codegen if not option.startswith(("metadata=", "extra-filename="))],
                         "compiler_wrapper": None, "incremental": False})
    if len(commands) != 1:
        raise ValueError("expected exactly one effective Rust runner compilation in verbose Cargo log")
    return commands


def source_hashes():
    files = [ROOT / "GOOSE_REVISION", ROOT / "scripts/compare.py", ROOT / "bench/parse.goose"]
    files.extend(ROOT.glob("*.goose"))
    files.extend((ROOT / "vendor").rglob("*.goose"))
    files.extend(path for path in ADAPTERS.rglob("*") if path.is_file())
    return {str(path.relative_to(ROOT)): digest(path) for path in sorted(files)
            if "__pycache__" not in path.parts}


def build(args):
    BUILD.mkdir(parents=True, exist_ok=True)
    env = fresh_env()
    cpp = ROOT / args.tomlplusplus
    if not cpp.is_dir():
        raise ValueError("tomlplusplus checkout missing; see bench/compare/README.md")
    if run(["git", "-C", cpp, "rev-parse", "HEAD"]).stdout.strip() != PIN:
        raise ValueError("tomlplusplus checkout is not the pinned full commit")
    if run(["git", "-C", cpp, "status", "--porcelain", "--untracked-files=no"]).stdout:
        raise ValueError("tomlplusplus has modified tracked files")
    goose = ROOT / args.goose
    before = source_hashes()
    repository = repository_snapshot()
    commands = [
        ([goose, "bench/compare/goose.goose", "--standalone", "-o", ".build/compare/goose-runner.c"], ROOT),
        (["gcc", "-O2", ".build/compare/goose-runner.c", "bench/compare/blackbox.c", "-o", ".build/compare/goose-runner", "-lm", "-ldl", "-lpthread"], ROOT),
        # Clean only this adapter package so every build emits its effective
        # rustc invocation even when dependency artifacts are already cached.
        (["cargo", "clean", "--package", "goose-toml-compare", "--release", "--target", rust_target(), "--manifest-path", "bench/compare/rust/Cargo.toml", "--target-dir", ".build/compare/rust"], ROOT),
        (["cargo", "build", "--release", "--locked", "--verbose", "--target", rust_target(), "--manifest-path", "bench/compare/rust/Cargo.toml", "--target-dir", ".build/compare/rust"], ROOT),
        (["go", "build", "-mod=readonly", "-trimpath", "-o", "../../../.build/compare/go-runner", "."], ADAPTERS / "go"),
        (["g++", "-std=c++17", "-O2", "-DNDEBUG", "-I" + str(cpp / "include"), "bench/compare/cpp/main.cpp", "-o", ".build/compare/cpp-runner"], ROOT),
    ]
    rust_commands = None
    for command, cwd in commands:
        print("Building " + ("Goose C" if command[0] == goose else Path(command[0]).name), flush=True)
        result = run(command, cwd=cwd, env=env)
        if command[:2] == ["cargo", "build"]:
            (BUILD / "cargo-build.log").write_text(result.stderr)
            rust_commands = verify_rust_commands(result.stderr)
            print("Verified effective Rust release options; local verbose log: .build/compare/cargo-build.log", flush=True)
            continue
        if result.stderr:
            # Build logs are local console output, not published report data.
            print(result.stderr.strip(), file=sys.stderr)
    if source_hashes() != before:
        raise ValueError("comparison or library sources changed during build; rebuild")
    cargo = json.loads(run(["cargo", "metadata", "--locked", "--format-version=1", "--manifest-path", "bench/compare/rust/Cargo.toml"], env=env).stdout)
    dependencies = [{"name": package["name"], "version": package["version"],
                     "license": package["license"], "repository": package["repository"],
                     "source": "https://crates.io/crates/" + package["name"] + "/" + package["version"]}
                    for package in cargo["packages"] if package["source"] is not None]
    packages = {package["name"]: package for package in dependencies}
    if packages["toml"]["version"] != RUST_PIN:
        raise ValueError("Cargo did not select exact toml " + RUST_PIN)
    locked = tomllib.loads((ADAPTERS / "rust/Cargo.lock").read_text())
    checksums = {(package["name"], package["version"]): package.get("checksum") for package in locked["package"]}
    for dependency in dependencies:
        dependency["archive_sha256"] = checksums[(dependency["name"], dependency["version"])]
    direct = json.loads((ADAPTERS / "dependencies.json").read_text())
    if packages["toml"]["archive_sha256"] != direct["dependencies"]["rust_toml"]["archive_sha256"]:
        raise ValueError("Rust crate checksum differs from official crates API pin")
    go_module = json.loads(run(["go", "list", "-m", "-json", "github.com/BurntSushi/toml"], cwd=ADAPTERS / "go", env=env).stdout)
    if go_module["Version"] != "v1.6.0":
        raise ValueError("Go module differs from pinned v1.6.0")
    version_commands = {"goose": [goose, "--version"], "gcc": ["gcc", "--version"],
                        "g++": ["g++", "--version"], "rustc": ["rustc", "-vV"],
                        "cargo": ["cargo", "--version"], "go": ["go", "version"]}
    metadata = {
        "schema": 1, "source_sha256": before,
        "repository_snapshot_before_build": repository,
        "binary_sha256": {name: digest(path) for name, path in binary_paths().items()},
        "tool_versions": {name: run(command, env=env).stdout.strip() for name, command in version_commands.items()},
        "dependencies": direct, "rust_transitive_dependencies": dependencies,
        "go_module_sum": go_module.get("Sum"), "cpp_commit": PIN,
        "goose_compiler_sha256": digest(goose),
        "generated_goose_c_sha256": digest(BUILD / "goose-runner.c"),
        "rust_build_environment_overrides": {**CARGO_OVERRIDES, "CARGO_BUILD_TARGET": rust_target(),
                                             "CARGO_TARGET_" + rust_target().upper().replace("-", "_") + "_LINKER": "cc"},
        "rust_effective_commands": rust_commands,
        "rust_verbose_build_log_sha256": digest(BUILD / "cargo-build.log"),
        "go_environment": json.loads(run(["go", "env", "-json", "GOOS", "GOARCH", "GOAMD64", "GOEXPERIMENT", "CGO_ENABLED"], env=env).stdout),
        "build_flags": {"goose": "standalone C, gcc -O2; no LTO or debug; separate C consumption barrier",
                        "cpp": "g++ -std=c++17 -O2 -DNDEBUG; default toml++ features; no LTO",
                        "rust": "cargo build --release --locked --verbose --target <rustc host>; enforced opt-level=3, codegen-units=16, lto=false, debug=false, incremental=false; no extra rustflags or compiler wrappers; default toml features",
                        "go": "go build -mod=readonly -trimpath; standard optimization; default GC (GOGC=100, GOMEMLIMIT=off)"},
        "build_cpu_affinity": sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
    }
    write_json(BUILD / "build.json", metadata)
    return metadata


def stats_of(value):
    stats = [0] * 12

    def visit(value):
        stats[0] += 1
        if isinstance(value, dict):
            stats[1] += 1
            for key, child in value.items():
                stats[7] += len(key.encode("utf-8"))
                visit(child)
        elif isinstance(value, list):
            stats[2] += 1
            for child in value:
                visit(child)
        elif isinstance(value, str):
            stats[3] += 1
            stats[8] += len(value.encode("utf-8"))
        elif isinstance(value, bool):
            stats[6] += 1
            stats[11] += int(value)
        elif isinstance(value, int):
            stats[4] += 1
            stats[9] += value
        elif isinstance(value, float):
            stats[5] += 1
            stats[10] += int(value * 1000)
        else:
            raise ValueError("unsupported corpus value")
    visit(value)
    return stats


def typed_equal(first, second):
    if type(first) is not type(second):
        return False
    if isinstance(first, dict):
        return first.keys() == second.keys() and all(typed_equal(first[key], second[key]) for key in first)
    if isinstance(first, list):
        return len(first) == len(second) and all(typed_equal(a, b) for a, b in zip(first, second))
    return first == second


def generate_cases(iterations):
    nested = lambda depth: "value=" + "{x=" * depth + "[" + "1," * 60000 + "]" + "}" * depth
    definitions = [
        ("small-config", "title = 'Goose'\n[server]\nport = 8080\nenabled = true\n", 1),
        ("wide-table", "".join(f"key{i} = {i}\n" for i in range(1000)), 100),
        ("float-array", "values = [" + "1.25," * 1000 + "]\n", 100),
        ("escaped-strings", "".join(f'key{i} = "Goose\\n\\u00e9\\U0001f600"\n' for i in range(100)), 100),
        ("integer-array", "values = [" + "123456," * 1000 + "]\n", 100),
        ("long-literal", "value = '" + "x" * 262144 + "'\n", 1000),
        ("array-then-key", "values = [" + "1," * 60000 + "]\ntrailing=1\n", 10000),
        ("nested-inline-array", nested(60), 10000),
    ]
    cases = []
    for name, source, divisor in definitions:
        path = BUILD / "cases" / (name + ".toml")
        path.parent.mkdir(parents=True, exist_ok=True)
        data = source.encode()
        if not path.exists() or path.read_bytes() != data:
            path.write_bytes(data)
        if len(data) > 1048576:
            raise ValueError("corpus exceeds Goose input limit")
        decoded = tomllib.loads(source)
        stats = stats_of(decoded)
        if stats[0] > 65536:
            raise ValueError("corpus exceeds Goose node limit")
        cases.append({"name": name, "file": str(path.relative_to(ROOT)), "input_bytes": len(data),
                      "sha256": digest(path), "input_fnv64": fingerprint(data),
                      "decoded_value_sha256": hashlib.sha256(json.dumps(decoded, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(),
                      "iterations": max(1, iterations // divisor), "root_count": len(decoded),
                      "stats": stats, "inline_depth": 60 if name == "nested-inline-array" else None})
    return cases


def invoke(name, case, iterations, mode, env):
    path = ROOT / case["file"]
    if digest(path) != case["sha256"]:
        raise ValueError("input changed after manifest generation")
    executable = binary_paths()["goose" if name == "goose_reuse" else name]
    runner_mode = mode + "-reuse" if name == "goose_reuse" else mode
    result = run([executable, path, iterations, runner_mode], env=env)
    if result.stderr.strip():
        raise ValueError(name + " emitted unexpected stderr: " + result.stderr[:300])
    if digest(path) != case["sha256"]:
        raise ValueError("input changed during runner execution")
    if mode == "write-decode":
        expected = tomllib.loads(path.read_text())
        decoded = tomllib.loads(result.stdout)
        if not typed_equal(expected, decoded):
            raise ValueError(name + " serialized TOML changes decoded values/types for " + case["name"])
        output = result.stdout.encode("utf-8")
        return {"serialized_bytes": len(output), "sha256": hashlib.sha256(output).hexdigest(),
                "first_byte": output[0] if output else 0, "last_byte": output[-1] if output else 0}
    value = strict_json(result.stdout)
    if mode == "decode":
        expected = tomllib.loads(path.read_text())
        if not typed_equal(expected, value):
            raise ValueError(name + " decoded values/types differ from independent Python tomllib for " + case["name"])
        return None
    fields = {"iterations", "input_bytes", "input_fnv64", "elapsed_ns"}
    fields |= {"serialized_bytes", "output_bytes_total", "output_edge_total"} if mode == "write" else {"root_total", "stats_total"}
    if not isinstance(value, dict) or set(value) != fields:
        raise ValueError("invalid runner response fields")
    integer_fields = fields - {"input_fnv64", "stats_total"}
    for field in integer_fields:
        if type(value[field]) is not int:
            raise ValueError("invalid runner integer field " + field)
    if value["iterations"] != iterations or value["input_bytes"] != case["input_bytes"] or value["input_fnv64"] != case["input_fnv64"]:
        raise ValueError("runner did not use identical input bytes/iteration count")
    if value["elapsed_ns"] <= 0:
        raise ValueError("invalid elapsed time")
    if mode == "write":
        expected = case["serialized_outputs"][name]
        if (value["serialized_bytes"] != expected["serialized_bytes"]
                or value["output_bytes_total"] != expected["serialized_bytes"] * iterations
                or value["output_edge_total"] != (expected["first_byte"] + expected["last_byte"]) * iterations):
            raise ValueError(name + " serialized output consumption differs from preflight for " + case["name"])
        return value
    if value["root_total"] != case["root_count"] * iterations:
        raise ValueError("invalid elapsed time or root consumption")
    expected = [count * iterations for count in case["stats"]] if mode == "full" else [0] * 12
    if type(value["stats_total"]) is not list or any(type(n) is not int for n in value["stats_total"]) or value["stats_total"] != expected:
        raise ValueError(name + " structural checksum mismatch for " + case["name"])
    return value


def preflight(cases, env, *, writer=False):
    probes = []
    nested = cases[-1]
    for name in NAMES:
        try:
            invoke(name, nested, 1, "decode", env)
            probes.append({"runner": name, "inline_depth": 60, "accepted": True})
        except subprocess.CalledProcessError as error:
            # Only an explicit native recursion/depth error permits substitution.
            message = error.stderr.strip()
            if not any(word in message.lower() for word in ("recursion", "nesting", "depth")):
                raise
            probes.append({"runner": name, "inline_depth": 60, "accepted": False,
                           "error": message[:1000].replace(str(ROOT), "<repository>")})
    if any(not probe["accepted"] for probe in probes):
        # Keep the original bytes and failure in the manifest; time an explicitly
        # named common-depth variant for every language, with the same 60k array.
        original = dict(nested)
        source = "value=" + "{x=" * 30 + "[" + "1," * 60000 + "]" + "}" * 30
        path = BUILD / "cases/nested-inline-array-depth30.toml"
        path.write_text(source)
        decoded = tomllib.loads(source)
        nested.update(name="nested-inline-array-depth30", file=str(path.relative_to(ROOT)),
                      sha256=digest(path), input_bytes=path.stat().st_size,
                      input_fnv64=fingerprint(path.read_bytes()), stats=stats_of(decoded), inline_depth=30,
                      decoded_value_sha256=hashlib.sha256(json.dumps(decoded, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest(),
                      replaced_case=original)
        print("Depth 60 was rejected; all runners will use the explicitly reported depth 30 variant.", flush=True)
    for case in cases:
        if writer:
            case["serialized_outputs"] = {}
        for name in NAMES:
            invoke(name, case, 1, "decode", env)
            invoke(name, case, 1, "full", env)
            if writer:
                case["serialized_outputs"][name] = invoke(name, case, 1, "write-decode", env)
                invoke(name, case, 1, "write", env)
    return probes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iterations", type=int, default=100000,
                        help="base count; per-case divisors match bench/parse.goose (default 100000)")
    parser.add_argument("--rounds", type=int, default=9)
    parser.add_argument("--cpu", type=int, help="allowed CPU; default minimum allowed, no exclusivity assumed")
    parser.add_argument("--seed", type=int, default=20261104)
    parser.add_argument("--mode", choices=("full", "root", "write"), default="full")
    parser.add_argument("--goose", type=Path, default=Path(".toolchain/goose/build/goose"))
    parser.add_argument("--tomlplusplus", type=Path, default=Path(".toolchain/tomlplusplus"))
    parser.add_argument("--output", type=Path, default=Path(".build/compare/report.json"))
    parser.add_argument("--no-build", action="store_true")
    parser.add_argument("--goose-reuse", action="store_true",
                        help="also measure destination reuse; results stay separate from fresh DOM medians")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--generate-only", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.iterations <= 1000000 or not 1 <= args.rounds <= 99:
        parser.error("iterations must be 1..1000000 and rounds 1..99")
    if args.mode == "write" and args.goose_reuse:
        parser.error("--goose-reuse applies to parsing modes only; write always creates fresh owned output")
    allowed = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    cpu = args.cpu if args.cpu is not None else (min(allowed) if allowed else None)
    if cpu is None or cpu not in allowed:
        parser.error("an allowed CPU and Linux affinity support are required")
    os.sched_setaffinity(0, {cpu})
    print(f"Pinned CPU {cpu}. Shared-machine measurement: this does not reserve or isolate the CPU.", file=sys.stderr)
    output = (ROOT / args.output).resolve()
    try:
        output.relative_to(BUILD)
    except ValueError:
        parser.error("published reports must stay under .build/compare")
    if args.generate_only:
        cases = generate_cases(args.iterations)
        write_json(BUILD / "cases/manifest.json", {"schema": 1, "cases": cases, "stats_fields": STATS})
        print("Generated eight cases and SHA-256 manifest in .build/compare/cases")
        return
    metadata = json.loads((BUILD / "build.json").read_text()) if args.no_build else build(args)
    if metadata["source_sha256"] != source_hashes():
        raise ValueError("sources changed since build metadata; rebuild without --no-build")
    if metadata["binary_sha256"] != {name: digest(path) for name, path in binary_paths().items()}:
        raise ValueError("binary changed since build metadata")
    if args.build_only:
        print("Built and recorded all runners in .build/compare/build.json")
        return
    cases = generate_cases(args.iterations)
    env = fresh_env()
    measured_names = NAMES + (("goose_reuse",) if args.goose_reuse else ())
    print("Checking every decoded value against Python tomllib, then validating full structural checksums.", flush=True)
    if args.mode == "write":
        print("Also independently decoding every serializer's actual TOML output and checking output consumption.", flush=True)
    depth_probes = preflight(cases, env, writer=args.mode == "write")
    manifest = {"schema": 1, "source": "bench/parse.goose", "stats_fields": STATS,
                "cases": cases, "depth_probes": depth_probes}
    write_json(BUILD / "cases/manifest.json", manifest)
    print("Warming all runners on all cases.", flush=True)
    for case in cases:
        for name in measured_names:
            invoke(name, case, max(1, case["iterations"] // 10), args.mode, env)
    samples = []
    unit = "write" if args.mode == "write" else "parse"
    sample_key = "ns_per_" + unit
    rng = random.Random(args.seed)
    for round_index in range(args.rounds):
        workloads = list(cases)
        rng.shuffle(workloads)
        for case in workloads:
            order = list(measured_names)
            rng.shuffle(order)
            for position, name in enumerate(order):
                value = invoke(name, case, case["iterations"], args.mode, env)
                samples.append({"round": round_index + 1, "case": case["name"], "runner": name,
                                "position": position, "cpu_affinity": [cpu], **value,
                                "input_sha256": case["sha256"],
                                sample_key: value["elapsed_ns"] / value["iterations"]})
        print(f"Completed paired round {round_index + 1}/{args.rounds}", flush=True)
        # Preserve raw progress even if a later process fails.
        write_json(BUILD / "samples.partial.json", samples)
    medians = {case["name"]: {
        name: statistics.median(sample[sample_key] for sample in samples
                                if sample["case"] == case["name"] and sample["runner"] == name)
        for name in NAMES} for case in cases}
    distributions = {}
    for case in cases:
        distributions[case["name"]] = {}
        for name in measured_names:
            values = [sample[sample_key] for sample in samples
                      if sample["case"] == case["name"] and sample["runner"] == name]
            median = statistics.median(values)
            distributions[case["name"]][name] = {
                "median_" + sample_key: median, "min_" + sample_key: min(values), "max_" + sample_key: max(values),
                "stdev_" + sample_key: statistics.stdev(values) if len(values) > 1 else 0,
                "median_absolute_deviation_" + sample_key: statistics.median(abs(value - median) for value in values),
            }
    cpu_model = platform.processor()
    if Path("/proc/cpuinfo").exists():
        cpu_model = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                          if line.startswith("model name")), cpu_model)
    report = {
        "schema": 1, "timestamp_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "measurement": "serialize a pre-parsed DOM to fresh owned output + length/edge consumption + scope cleanup" if args.mode == "write"
                       else "fresh owned DOM parse + full structural checksum visit + scope cleanup" if args.mode == "full"
                       else "fresh owned DOM parse + immediate root count + scope cleanup (no structural visit)",
        "mode": args.mode, "rounds": args.rounds, "seed": args.seed,
        "platform": platform.platform(), "cpu_model": cpu_model, "cpu_affinity": [cpu],
        "allowed_cpu_affinity_before_pinning": allowed, "shared_machine": True,
        "independent_preflight": "Every decoded value and type compared with Python " + platform.python_version() + " tomllib before timing",
        "manifest": manifest, "build": metadata, "median_" + sample_key: medians, "samples": samples,
        "sample_distributions": distributions,
        "goose_reuse_median_ns_per_parse": {
            case["name"]: distributions[case["name"]]["goose_reuse"]["median_ns_per_parse"] for case in cases
        } if args.goose_reuse else None,
        "limitations": [
            "Warm process throughput, input file reading/fingerprinting outside timer; same bytes/counts in every runner. New process per sample.",
            "CPU affinity does not grant exclusivity; other host work, frequency changes and short samples can dominate. No portable performance winner is inferred.",
            "Goose uses compiler-managed data stacks with scope cleanup and retained backing pages; Rust/C++ use their standard owned containers/allocators; Go uses a fresh map and enabled amortized GC. No forced allocator clearing, page trimming, or GC collection.",
            "Go GC work during the loop is included; collection of unreachable objects after the timed loop is not forced. This is not allocation-normalized or memory-usage measurement.",
            "Full mode includes a semantic node visit and key/string byte-length counts, integer/boolean values and floats scaled by 1000; it does not hash every string byte. Decoded content is independently checked before timing.",
            "In full parsing mode Goose visits its flat node buffer; Rust/C++/Go visit trees/maps. The cost reflects each DOM representation. Root mode is available separately.",
            "Default parser limits, table/index strategies, caches, numeric conversion and datetime representations/precision stay enabled. Corpus uses only tables, arrays, UTF-8 strings, bools, i64-range integers and exactly representable 1.25 floats; no datetime cost or precision comparison is claimed.",
            "Rust toml supports TOML 1.1; these shared inputs use TOML 1.0 constructs. Goose parses in its strict default TOML 1.0 mode.",
        ],
    }
    if args.mode == "write":
        report["independent_preflight"] += "; every serializer's TOML output was reparsed by Python tomllib and compared by decoded value/type"
        report["serializer_apis"] = {"goose": "toml::serialize", "rust": "toml::to_string",
                                     "go": "toml.Marshal", "cpp": "toml::toml_formatter into a fresh std::ostringstream, then str()"}
        report["limitations"].extend([
            "Write mode parses the input once outside the timer and serializes that DOM repeatedly. Every iteration creates fresh owned output; input parsing is not included in writer timings.",
            "Default serializers choose different whitespace, ordering, quoting, inline tables/headers and line wrapping. Per-language output byte sizes and SHA-256 are recorded in each case's serialized_outputs. Equal decoded values do not mean identical formatting work or bytes.",
            "Default public APIs have different validation, scratch allocation, copying and numeric formatting costs. Those costs remain included; no common formatting policy or validation level is forced, and no universal serializer winner is implied.",
            "Each writer consumes output byte length plus first/last bytes through a consumption barrier or non-inlined Go call and KeepAlive. Full output contents are validated independently before timing; no full-output hash or decode is timed.",
        ])
    if source_hashes() != metadata["source_sha256"]:
        raise ValueError("sources changed during measurement; raw partial samples retained, rebuild before publishing")
    write_json(output, report)
    print("case | Goose | Rust | Go | C++ (median ns/" + unit + ")")
    for case, values in medians.items():
        print(case + " | " + " | ".join(f"{values[name]:.1f}" for name in NAMES))
    if args.goose_reuse:
        print("Separate Goose destination-reuse medians (ns/parse):")
        for case in cases:
            print(case["name"] + " | " + str(distributions[case["name"]]["goose_reuse"]["median_ns_per_parse"]))
    print("Wrote " + str(output.relative_to(ROOT)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
        print("Comparison failed: " + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr[:4000], file=sys.stderr)
        sys.exit(1)
