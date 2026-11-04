GOOSE ?= .toolchain/goose/build/goose
.PHONY: setup check test format
setup:
	./scripts/setup-goose.sh
check:
	$(GOOSE) format --check toml.goose vendor/text.goose examples tests bench
	$(GOOSE) check tests/utf8.goose
	$(GOOSE) check tests/parser.goose
	$(GOOSE) check tests/lifecycle.goose
	$(GOOSE) check tests/fuzz.goose
	$(GOOSE) check examples/config.goose
	$(GOOSE) check tests/decoder.goose
	$(GOOSE) check bench/parse.goose
test:
	$(GOOSE) run tests/utf8.goose
	mkdir -p .build
	$(GOOSE) build tests/utf8.goose -o .build/utf8
	./.build/utf8
	$(GOOSE) run tests/parser.goose
	$(GOOSE) run tests/lifecycle.goose
	mkdir -p .build
	$(GOOSE) build tests/parser.goose -o .build/parser
	./.build/parser
	$(GOOSE) build tests/lifecycle.goose -o .build/lifecycle
	./.build/lifecycle
	$(GOOSE) run examples/config.goose
format:
	$(GOOSE) format toml.goose vendor/text.goose examples tests bench

.PHONY: conformance
conformance:
	./scripts/setup-toml-test.sh
	mkdir -p .build
	$(GOOSE) build tests/decoder.goose -o .build/decoder
	.build/toml-test test -decoder=.build/decoder -toml=1.0 -color=never

BENCH_ITERATIONS ?= 10000
.PHONY: bench
bench:
	mkdir -p .build
	$(GOOSE) build bench/parse.goose --cc gcc -O2 -o .build/bench
	./.build/bench $(BENCH_ITERATIONS)

.PHONY: property sanitize
property:
	python3 -m unittest discover -s tests -p test_validation.py
	mkdir -p .build
	$(GOOSE) build tests/decoder.goose -o .build/decoder
	python3 scripts/property-test.py --decoder .build/decoder
sanitize:
	mkdir -p .build
	$(GOOSE) tests/parser.goose --standalone --debug --no-bce -o .build/parser-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/parser-sanitized .build/parser-sanitized.c -lm -ldl -lpthread
	./.build/parser-sanitized
	$(GOOSE) tests/lifecycle.goose --standalone --debug --no-bce -o .build/lifecycle-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/lifecycle-sanitized .build/lifecycle-sanitized.c -lm -ldl -lpthread
	./.build/lifecycle-sanitized
	$(GOOSE) tests/decoder.goose --standalone --debug --no-bce -o .build/decoder-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/decoder-sanitized .build/decoder-sanitized.c -lm -ldl -lpthread
	python3 scripts/security-test.py --decoder .build/decoder-sanitized

.PHONY: security
security:
	mkdir -p .build
	$(GOOSE) build tests/decoder.goose -o .build/decoder
	python3 scripts/security-test.py --decoder .build/decoder

FUZZ_SECONDS ?= 30
FUZZ_RUNS ?= 100000
FUZZ_SEED ?= 20261104
FUZZ_CC ?= clang
.PHONY: fuzz
fuzz:
	python3 scripts/fuzz.py --goose "$(GOOSE)" --cc "$(FUZZ_CC)" --seconds "$(FUZZ_SECONDS)" --runs "$(FUZZ_RUNS)" --seed "$(FUZZ_SEED)"
