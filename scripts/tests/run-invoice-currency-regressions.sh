#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-invoice-currency.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Invoice.swift" \
  "$repo_root/ProEstimate AI/Core/Models/CurrencyDisplay.swift" \
  "$repo_root/ProEstimate AI/Core/Models/InvoiceCurrencyBalance.swift" \
  "$repo_root/scripts/tests/InvoiceCurrencyRegressionTests.swift" \
  -o "$build_dir/invoice-currency"
"$build_dir/invoice-currency"
