#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-estimate-editor.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Estimate.swift" \
  "$repo_root/ProEstimate AI/Core/Models/EstimateLineItem.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Models/EstimateLineItemForm.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Services/EstimateEditing.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/ViewModels/EstimateEditorViewModel.swift" \
  "$repo_root/scripts/tests/EstimateEditorRegressionTests.swift" \
  -o "$build_dir/estimate-editor-regressions"
"$build_dir/estimate-editor-regressions"
