#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-estimate-delivery.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun swiftc -swift-version 5 -default-isolation MainActor -strict-concurrency=complete -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Client.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Estimate.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Proposal.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Invoice.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Creation/Models/EstimateCreationDraft.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Delivery/Models/EstimateDeliveryModels.swift" \
  "$repo_root/ProEstimate AI/Features/Estimates/Delivery/ViewModels/EstimateDeliveryViewModel.swift" \
  "$repo_root/ProEstimate AI/Features/Proposals/Services/ProposalService.swift" \
  "$repo_root/ProEstimate AI/Features/Proposals/Models/ProposalDocumentForm.swift" \
  "$repo_root/scripts/tests/EstimateDeliveryRegressionTests.swift" \
  -o "$build_dir/estimate-delivery-regressions"
"$build_dir/estimate-delivery-regressions"
