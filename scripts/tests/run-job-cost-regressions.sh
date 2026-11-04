#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-job-costs.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Client.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Estimate.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateCreationDraft.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateDraftCheckpoint.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Services/EstimateDraftStore.swift" \
  "$repo_root/ProEstimate AI/Features/JobCosts/Models/JobCostModels.swift" \
  "$repo_root/ProEstimate AI/Features/JobCosts/Services/JobCostPendingJournal.swift" \
  "$repo_root/ProEstimate AI/Features/JobCosts/Services/JobCostReceiptFiles.swift" \
  "$repo_root/ProEstimate AI/Features/JobCosts/ViewModels/JobCostViewModel.swift" \
  "$repo_root/scripts/tests/JobCostRegressionTests.swift" \
  -o "$build_dir/job-cost-regressions"
"$build_dir/job-cost-regressions"
