#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-payment-settings.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Features/CustomerPayments/CustomerPaymentSettingsViewModel.swift" \
  "$repo_root/scripts/tests/CustomerPaymentSettingsRegressionTests.swift" \
  -o "$build_dir/payment-settings-regressions"
"$build_dir/payment-settings-regressions"
