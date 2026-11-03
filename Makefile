GOOSE ?= .toolchain/goose/build/goose
.PHONY: setup check test format
setup:
	./scripts/setup-goose.sh
check:
	$(GOOSE) format --check toml.goose examples tests
	$(GOOSE) check tests/parser.goose
	$(GOOSE) check examples/config.goose
test:
	$(GOOSE) run tests/parser.goose
	mkdir -p .build
	$(GOOSE) build tests/parser.goose -o .build/parser
	./.build/parser
	$(GOOSE) run examples/config.goose
format:
	$(GOOSE) format toml.goose examples tests
