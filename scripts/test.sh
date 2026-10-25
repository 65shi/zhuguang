#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/smartlight-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_BUILD_DIR"' EXIT
xcrun swiftc -parse-as-library \
    "$PROJECT_DIR/Sources/Zhuguang/BoostPolicy.swift" \
    "$PROJECT_DIR/Tests/ZhuguangTests/BoostPolicyTests.swift" \
    -o "$TEST_BUILD_DIR/policy-checks"
"$TEST_BUILD_DIR/policy-checks"
cd -- "$PROJECT_DIR"
xcrun swift build
