#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Native Linux platform gate. EXPECTED_ARCH prevents a mislabeled runner from
# being reported as architecture evidence. QEMU availability alone is not a pass.
set -euo pipefail
cd "$(dirname "$0")/.."

platform_os=$(uname -s)
platform_arch=$(uname -m)
case "$platform_arch" in
    aarch64|arm64) platform_arch=aarch64 ;;
    x86_64|amd64|AMD64) platform_arch=x86_64 ;;
    *) printf 'Unsupported platform architecture: %s\n' "$platform_arch" >&2; exit 2 ;;
esac
expected_arch=${EXPECTED_ARCH:-$platform_arch}
case "$expected_arch" in
    aarch64|arm64) expected_arch=aarch64 ;;
    x86_64|amd64|AMD64) expected_arch=x86_64 ;;
    *) printf 'Unsupported EXPECTED_ARCH: %s\n' "$expected_arch" >&2; exit 2 ;;
esac
if [[ "$platform_os" != Linux || "$platform_arch" != "$expected_arch" ]]; then
    printf 'Expected native Linux %s; found %s %s\n' "$expected_arch" "$platform_os" "$platform_arch" >&2
    exit 2
fi
if [[ $(getconf LONG_BIT) != 64 ]]; then
    printf 'The pinned Goose toolchain requires a 64-bit userspace\n' >&2
    exit 2
fi
for platform_tool in git cmake make gcc g++ python3 go; do
    if ! command -v "$platform_tool" >/dev/null 2>&1; then
        printf 'Missing platform-check prerequisite: %s\n' "$platform_tool" >&2
        exit 2
    fi
done
# Record the source, actual kernel/CPU architecture and compiler target in CI
# logs. Successful source-only generation or cross-compilation is insufficient.
printf 'Checking native %s %s at source ' "$platform_os" "$platform_arch"
git rev-parse HEAD
uname -srm
gcc -dumpmachine
python3 --version
cmake --version
gcc --version
go version
printf 'Pinned Goose revision: '
cat GOOSE_REVISION

# Force the freshly provisioned pinned compiler even if GOOSE is set by a caller.
# test executes the public parser/editor/writer API in-process and through native
# binaries; conformance independently checks both decoder and encoder versions.
make GOOSE=.toolchain/goose/build/goose setup check test conformance property scalar security
printf 'Passed native %s %s: check test conformance property scalar security\n' "$platform_os" "$platform_arch"
