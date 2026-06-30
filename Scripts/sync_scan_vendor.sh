#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Server/Vendor"

mkdir -p "$VENDOR/OffsendReportCore"
rsync -a --delete "$ROOT/Core/WorkspacePolicyCore/" "$VENDOR/WorkspacePolicyCore/"
cp "$ROOT/Core/OffsendRuntime/Sources/ReportReporter.swift" "$VENDOR/OffsendReportCore/"
rm -f "$VENDOR/OffsendReportCore/OffsendReportService.swift"

echo "Synced scan vendor sources into Server/Vendor"
