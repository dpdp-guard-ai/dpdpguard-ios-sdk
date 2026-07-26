#!/usr/bin/env bash
# Vendors openapi/v1.yaml + conformance/* from @dpdpguard/contract into contract/.
# These files are committed (Swift Package Manager has no npm devDependency
# equivalent), so re-run this script and commit the diff whenever the
# contract package bumps a version.
set -euo pipefail

VERSION="${1:-latest}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/contract"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Fetching @dpdpguard/contract@${VERSION}..."
(cd "$TMP_DIR" && npm pack "@dpdpguard/contract@${VERSION}" --silent)

TARBALL="$(find "$TMP_DIR" -maxdepth 1 -name '*.tgz')"
tar -xzf "$TARBALL" -C "$TMP_DIR"

RESOLVED_VERSION="$(node -p "require('$TMP_DIR/package/package.json').version")"

rm -rf "$DEST"
mkdir -p "$DEST/openapi" "$DEST/conformance"
cp "$TMP_DIR/package/openapi/v1.yaml" "$DEST/openapi/v1.yaml"
cp "$TMP_DIR/package/conformance/error-catalog.json" "$DEST/conformance/error-catalog.json"
cp "$TMP_DIR/package/conformance/audit-hash-vectors.json" "$DEST/conformance/audit-hash-vectors.json"
cp "$TMP_DIR/package/conformance/audit-hash-spec.md" "$DEST/conformance/audit-hash-spec.md"
echo "$RESOLVED_VERSION" > "$DEST/CONTRACT_VERSION"

# Mirror the spec into the generator target's source dir - the
# OpenAPIGenerator build plugin requires openapi.yaml to live alongside the
# Swift sources it generates into, not in an arbitrary repo-root location.
cp "$DEST/openapi/v1.yaml" "$REPO_ROOT/Sources/DPDPGuardConsentAPI/openapi.yaml"

echo "Vendored @dpdpguard/contract@${RESOLVED_VERSION} into contract/"
