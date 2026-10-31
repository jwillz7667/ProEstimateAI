#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-comparison.XXXXXX")"
trap 'rm -f "$build_dir/comparison-regressions"; rmdir "$build_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_root/ProEstimate AI/Features/Projects/Detail/Components/BeforeAfterComparisonGeometry.swift" \
  "$repo_root/scripts/tests/BeforeAfterComparisonTests.swift" \
  -o "$build_dir/comparison-regressions"

"$build_dir/comparison-regressions"
