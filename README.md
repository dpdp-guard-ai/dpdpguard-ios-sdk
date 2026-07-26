# dpdpguard-ios-sdk

DPDP Guard iOS SDK (Swift) - native consent banner, on-device gating, offline durability

Package: `DPDPGuardConsent`

Part of the DPDP Guard SDK family. See the design spec:
https://github.com/chintans/dpdpbot/blob/main/docs/specs/mobile-server-sdk.md

## Contract

This SDK's HTTP client is generated from [`@dpdpguard/contract`](https://www.npmjs.com/package/@dpdpguard/contract),
the versioned OpenAPI spec + ADR-002 error catalog + audit-hash conformance
vectors shared by every DPDP Guard SDK (server, Android, iOS, RN, Flutter).

- `contract/` — vendored copy of the contract package's `openapi/v1.yaml` and
  `conformance/*`, pinned in `contract/CONTRACT_VERSION`. Swift Package
  Manager has no npm-style devDependency, so these files are fetched and
  committed rather than resolved at build time.
- `Sources/DPDPGuardConsentAPI/` — the client target. `openapi.yaml` +
  `openapi-generator-config.yaml` here drive Apple's
  [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator)
  build plugin, which generates `Types.swift`/`Client.swift` at build time
  (not committed).
- `Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift` — generated from
  `conformance/error-catalog.json`; committed, regenerate with the script
  below rather than hand-editing.
- `Sources/DPDPGuardConsent/AuditHash.swift` — hand-written HMAC-SHA256
  canonicalization per `conformance/audit-hash-spec.md`, verified against
  the golden vectors in `Tests/DPDPGuardConsentTests/AuditHashConformanceTests.swift`.

### Updating to a new contract version

```bash
./scripts/update-contract.sh 0.3.0   # or "latest"
node scripts/generate-error-codes.mjs
swift build && swift test
```

Commit the diff in `contract/`, `Sources/DPDPGuardConsentAPI/openapi.yaml`,
and `Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift` together.

## Build, test, publish

```bash
swift build
swift test
```

Publishing is git-tag based — Swift Package Manager resolves packages
directly from git, there is no separate registry push:

```bash
git tag 1.0.0
git push origin 1.0.0
```

Consumers add this repo's URL in Xcode (File → Add Package Dependencies) or
in their own `Package.swift`:

```swift
.package(url: "https://github.com/chintans/dpdpguard-ios-sdk.git", from: "1.0.0")
```
