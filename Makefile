GOOSE ?= .toolchain/goose/build/goose
.PHONY: setup check test format
setup:
	./scripts/setup-goose.sh
check:
	$(GOOSE) format --check toml.goose examples tests bench
	$(GOOSE) check tests/parser.goose
	$(GOOSE) check examples/config.goose
	$(GOOSE) check tests/decoder.goose
	$(GOOSE) check bench/parse.goose
test:
	$(GOOSE) run tests/parser.goose
	mkdir -p .build
	$(GOOSE) build tests/parser.goose -o .build/parser
	./.build/parser
	$(GOOSE) run examples/config.goose
format:
	$(GOOSE) format toml.goose examples tests bench

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
