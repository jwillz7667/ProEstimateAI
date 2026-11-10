#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-invoice-finance.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Client.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Estimate.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Invoice.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateCreationDraft.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateDraftCheckpoint.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Services/EstimateDraftStore.swift" \
  "$repo_root/ProEstimate AI/Features/Invoices/Finance/Models/InvoiceFinanceModels.swift" \
  "$repo_root/ProEstimate AI/Features/Invoices/Finance/Services/InvoicePaymentJournal.swift" \
  "$repo_root/ProEstimate AI/Features/Invoices/Finance/ViewModels/InvoiceFinanceViewModel.swift" \
  "$repo_root/scripts/tests/InvoiceFinanceRegressionTests.swift" \
  -o "$build_dir/invoice-finance-regressions"
"$build_dir/invoice-finance-regressions"
