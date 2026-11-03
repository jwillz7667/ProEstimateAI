#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-direct-creation.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Client.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Estimate.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateCreationDraft.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateDraftCheckpoint.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/ViewModels/EstimateCreationViewModel.swift" \
  "$repo_root/scripts/tests/EstimateCreationRegressionTests.swift" \
  -o "$build_dir/estimate-creation-regressions"
"$build_dir/estimate-creation-regressions"
