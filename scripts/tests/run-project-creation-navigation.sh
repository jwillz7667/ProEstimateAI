#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/proestimate-creation-navigation.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  "$repo_root/ProEstimate AI/Core/Models/Project.swift" \
  "$repo_root/ProEstimate AI/Features/Projects/Creation/Models/ProjectCreationModels.swift" \
  "$repo_root/scripts/tests/ProjectCreationNavigationTests.swift" \
  -o "$build_dir/creation-navigation"

"$build_dir/creation-navigation"
