GOOSE ?= .toolchain/goose/build/goose
.PHONY: setup check test format
setup:
	./scripts/setup-goose.sh
check:
	$(GOOSE) format --check toml.goose document.goose writer.goose vendor/text.goose examples tests bench
	$(GOOSE) check tests/spec11.goose
	$(GOOSE) check tests/document.goose
	$(GOOSE) check tests/writer.goose
	$(GOOSE) check tests/mutation.goose
	$(GOOSE) check tests/utf8.goose
	$(GOOSE) check tests/parser.goose
	$(GOOSE) check tests/scalars.goose
	$(GOOSE) check tests/lifecycle.goose
	$(GOOSE) check tests/fuzz.goose
	$(GOOSE) check examples/config.goose
	$(GOOSE) check tests/decoder.goose
	$(GOOSE) check tests/encoder.goose
	$(GOOSE) check bench/parse.goose
test:
	$(GOOSE) run tests/utf8.goose
	mkdir -p .build
	$(GOOSE) build tests/utf8.goose -o .build/utf8
	./.build/utf8
	$(GOOSE) run tests/parser.goose
	$(GOOSE) run tests/lifecycle.goose
	$(GOOSE) run tests/spec11.goose
	$(GOOSE) run tests/document.goose
	$(GOOSE) run tests/writer.goose
	$(GOOSE) run tests/mutation.goose
	mkdir -p .build
	$(GOOSE) build tests/parser.goose -o .build/parser
	./.build/parser
	$(GOOSE) build tests/lifecycle.goose -o .build/lifecycle
	./.build/lifecycle
	$(GOOSE) build tests/spec11.goose -o .build/spec11
	./.build/spec11
	$(GOOSE) build tests/document.goose -o .build/document
	./.build/document
	$(GOOSE) build tests/writer.goose -o .build/writer
	./.build/writer
	$(GOOSE) build tests/mutation.goose -o .build/mutation
	./.build/mutation
	$(GOOSE) run examples/config.goose
format:
	$(GOOSE) format toml.goose document.goose writer.goose vendor/text.goose examples tests bench

.PHONY: conformance
conformance:
	./scripts/setup-toml-test.sh
	mkdir -p .build
	$(GOOSE) build tests/decoder.goose -o .build/decoder
	$(GOOSE) build tests/encoder.goose -o .build/encoder
	.build/toml-test test -decoder=.build/decoder -encoder=.build/encoder -toml=1.0 -color=never
	.build/toml-test test '-decoder=.build/decoder --toml=1.1' -encoder=.build/encoder -toml=1.1 -color=never

BENCH_ITERATIONS ?= 10000
.PHONY: bench
bench:
	mkdir -p .build
	$(GOOSE) build bench/parse.goose --cc gcc -O2 -o .build/bench
	./.build/bench $(BENCH_ITERATIONS)

.PHONY: property sanitize
property:
	python3 -m unittest discover -s tests -p 'test_*.py'
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
	@for target in spec11 document writer mutation; do \
		$(GOOSE) tests/$$target.goose --standalone --debug --no-bce -o .build/$$target-sanitized.c && \
		gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/$$target-sanitized .build/$$target-sanitized.c -lm -ldl -lpthread && \
		./.build/$$target-sanitized || exit $$?; \
	done
	$(GOOSE) tests/scalars.goose --standalone --debug --no-bce -o .build/scalars-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/scalars-sanitized .build/scalars-sanitized.c -lm -ldl -lpthread
	python3 -O scripts/scalar-test.py --runner .build/scalars-sanitized
	$(GOOSE) tests/decoder.goose --standalone --debug --no-bce -o .build/decoder-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/decoder-sanitized .build/decoder-sanitized.c -lm -ldl -lpthread
	python3 scripts/security-test.py --decoder .build/decoder-sanitized
	$(GOOSE) tests/encoder.goose --standalone --debug --no-bce -o .build/encoder-sanitized.c
	gcc -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -o .build/encoder-sanitized .build/encoder-sanitized.c -lm -ldl -lpthread
	python3 scripts/encoder-test.py --encoder .build/encoder-sanitized

.PHONY: security
security:
	mkdir -p .build
	$(GOOSE) build tests/decoder.goose -o .build/decoder
	python3 scripts/security-test.py --decoder .build/decoder
	$(GOOSE) build tests/encoder.goose -o .build/encoder
	python3 scripts/encoder-test.py --encoder .build/encoder

FUZZ_SECONDS ?= 30
FUZZ_RUNS ?= 100000
FUZZ_SEED ?= 20261104
FUZZ_CC ?= clang
.PHONY: fuzz
fuzz:
	python3 scripts/fuzz.py --goose "$(GOOSE)" --cc "$(FUZZ_CC)" --seconds "$(FUZZ_SECONDS)" --runs "$(FUZZ_RUNS)" --seed "$(FUZZ_SEED)"

.PHONY: scalar
scalar:
	mkdir -p .build
	$(GOOSE) build tests/scalars.goose --cc gcc -O2 -o .build/scalars
	python3 scripts/scalar-test.py --runner .build/scalars
