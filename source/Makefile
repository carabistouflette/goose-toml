GOOSE ?= ../.toolchain/goose/build/goose
CC ?= gcc
SANITIZER_CC ?= gcc
.NOTPARALLEL:
.PHONY: format check test property conformance sanitize
format:
	"$(GOOSE)" format editor.goose tests bench.goose
check:
	"$(GOOSE)" format --check editor.goose tests bench.goose
	"$(GOOSE)" check tests/overloads.goose
	"$(GOOSE)" check tests/editor.goose
	"$(GOOSE)" check tests/oracle.goose
	"$(GOOSE)" check tests/index.goose
	"$(GOOSE)" check tests/fuzz.goose
	"$(GOOSE)" check bench.goose
test:
	mkdir -p .build
	"$(GOOSE)" run tests/overloads.goose
	"$(GOOSE)" build tests/overloads.goose --cc "$(CC)" -O2 -o .build/overloads
	./.build/overloads
	"$(GOOSE)" build tests/overloads.goose --cc "$(CC)" --debug --no-bce -o .build/overloads-debug
	./.build/overloads-debug
	"$(GOOSE)" run tests/editor.goose
	"$(GOOSE)" build tests/editor.goose --cc "$(CC)" -O2 -o .build/editor
	./.build/editor
	"$(GOOSE)" build tests/editor.goose --cc "$(CC)" --debug --no-bce -o .build/editor-debug
	./.build/editor-debug
property:
	mkdir -p .build
	"$(GOOSE)" build tests/oracle.goose --cc "$(CC)" -O2 -o .build/oracle
	python3 tests/model.py .build/oracle
	"$(GOOSE)" build tests/oracle.goose --cc "$(CC)" --debug --no-bce -o .build/oracle-debug
	python3 tests/model.py .build/oracle-debug
conformance:
	mkdir -p .build
	"$(GOOSE)" build tests/index.goose --cc "$(CC)" -O2 -o .build/index
	python3 tests/conformance.py .build/index
sanitize:
	mkdir -p .build
	SANITIZER_CC="$(SANITIZER_CC)" "$(GOOSE)" build tests/overloads.goose --cc "$(abspath sanitizer-cc.sh)" --standalone --debug --no-bce -o .build/overloads-sanitize
	ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 ./.build/overloads-sanitize
	SANITIZER_CC="$(SANITIZER_CC)" "$(GOOSE)" build tests/editor.goose --cc "$(abspath sanitizer-cc.sh)" --standalone --debug --no-bce -o .build/editor-sanitize
	ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 ./.build/editor-sanitize
	SANITIZER_CC="$(SANITIZER_CC)" "$(GOOSE)" build tests/oracle.goose --cc "$(abspath sanitizer-cc.sh)" --standalone -O2 --no-bce -o .build/oracle-sanitize
	ASAN_OPTIONS=detect_leaks=1 UBSAN_OPTIONS=halt_on_error=1 python3 tests/model.py .build/oracle-sanitize

FUZZ_SECONDS ?= 30
FUZZ_RUNS ?= 100000
.PHONY: fuzz
fuzz:
	python3 scripts/fuzz.py --goose "$(GOOSE)" --seconds "$(FUZZ_SECONDS)" --runs "$(FUZZ_RUNS)"

BENCH_ITERATIONS ?= 100
.PHONY: bench
bench:
	mkdir -p .build
	python3 scripts/benchmark.py --snapshot
	"$(GOOSE)" build bench.goose --cc "$(CC)" -O2 -o .build/bench
	BENCH_CC="$(CC)" python3 scripts/benchmark.py .build/bench $(BENCH_ITERATIONS)
