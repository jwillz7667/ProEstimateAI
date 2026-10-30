#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-ios-regressions.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_root/ProEstimate AI/App/AppConstants.swift" \
  "$repo_root/ProEstimate AI/Features/Auth/Models/AuthFormValidation.swift" \
  "$repo_root/ProEstimate AI/Features/Auth/Models/OAuthRequestSecurity.swift" \
  "$repo_root/ProEstimate AI/Features/Auth/Models/AuthModels.swift" \
  "$repo_root/ProEstimate AI/Core/Models/User.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Company.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Invoice.swift" \
  "$repo_root/ProEstimate AI/Core/Models/InvoiceLineItem.swift" \
  "$repo_root/ProEstimate AI/Features/Invoices/Services/InvoiceService.swift" \
  "$repo_root/ProEstimate AI/Features/Invoices/ViewModels/InvoiceDetailViewModel.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Commerce/SubscriptionState.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Commerce/EntitlementSnapshot.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Commerce/StoreProductModel.swift" \
  "$repo_root/ProEstimate AI/Core/Models/Commerce/PaywallDecision.swift" \
  "$repo_root/ProEstimate AI/Features/Commerce/Protocols/CommerceAPIClientProtocol.swift" \
  "$repo_root/ProEstimate AI/Features/Commerce/Services/EntitlementStore.swift" \
  "$repo_root/ProEstimate AI/Features/Commerce/Services/UsageMeterStore.swift" \
  "$repo_root/ProEstimate AI/Features/Commerce/Services/CommerceTransactionDelivery.swift" \
  "$repo_root/ProEstimate AI/Features/Commerce/Mocks/MockCommerceAPIClient.swift" \
  "$repo_root/ProEstimate AI/App/PaywallPresenter.swift" \
  "$repo_root/ProEstimate AI/Core/Networking/APIError.swift" \
  "$repo_root/ProEstimate AI/Core/Networking/APIResponseEnvelope.swift" \
  "$repo_root/scripts/tests/IOSDisplayTestSupport.swift" \
  "$repo_root/scripts/tests/IOSRegressionTests.swift" \
  -o "$build_dir/ios-regressions"

"$build_dir/ios-regressions"
