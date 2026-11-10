#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-dashboard-regressions.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/App/AppConstants.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Features/Dashboard/Models/DashboardModels.swift" \
  "$repo_root/ProEstimate AI/Features/Dashboard/Models/DashboardAttention.swift" \
  "$repo_root/ProEstimate AI/Features/Dashboard/ViewModels/DashboardViewModel.swift" \
  "$repo_root/scripts/tests/DashboardRegressionTests.swift" \
  -o "$build_dir/dashboard-regressions"

"$build_dir/dashboard-regressions"
