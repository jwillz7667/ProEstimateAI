#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-proposal-followup.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Proposal.swift" \
  "$repo_root/ProEstimate AI/Features/Proposals/Models/ProposalDocumentForm.swift" \
  "$repo_root/ProEstimate AI/Features/Proposals/Services/ProposalService.swift" \
  "$repo_root/ProEstimate AI/Features/FollowUps/Models/FollowUpModels.swift" \
  "$repo_root/ProEstimate AI/Features/FollowUps/ViewModels/FollowUpViewModels.swift" \
  "$repo_root/scripts/tests/ProposalFollowUpRegressionTests.swift" \
  -o "$build_dir/proposal-followup-regressions"
"$build_dir/proposal-followup-regressions"
