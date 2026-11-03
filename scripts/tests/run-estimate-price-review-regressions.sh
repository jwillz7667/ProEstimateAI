#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-price-review.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/EstimateLineItem.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Models/EstimatePriceReview.swift" \
  "$repo_root/scripts/tests/EstimatePriceReviewTests.swift" \
  -o "$build_dir/price-review"
"$build_dir/price-review"
