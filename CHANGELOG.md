# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-07-29

Major version bump forced by the upstream `@dpdpguard/contract` 1.0.0
breaking change (tightened request-body validation on several fields,
optional `Idempotency-Key` on grievance filing). No functional changes
needed in this SDK — this release exists solely to satisfy ADR-002 D3/D4's
requirement that a contract major bump forces a major bump in every
dependent SDK. Tag/release cut via the `workflow_dispatch` fallback in
`publish.yml` (tag `push` was unavailable in the automation environment
that prepared this release).

## [0.1.0] - 2026-07-26

Initial release. This SDK's HTTP client, error types, and audit-hash
implementation are generated/verified from
[`@dpdpguard/contract@0.2.0`](https://www.npmjs.com/package/@dpdpguard/contract) —
the same versioned OpenAPI spec, error catalog, and conformance vectors
shared by the Android, RN, Flutter, and server SDKs.

### Added

- `DPDPGuardConsent` library target (`Package.swift`), Swift 5.9 tools
  version, iOS 14+.
- `DPDPGuardConsentAPI` target wiring Apple's
  [`swift-openapi-generator`](https://github.com/apple/swift-openapi-generator)
  build plugin against the vendored `openapi/v1.yaml`, generating
  `Types.swift`/`Client.swift` for all 25 `/api/v1` and `/cm/v1/consent`
  operations at build time.
- `ApiErrorCode`, a generated Swift enum of the 10 ADR-002 machine-readable
  error codes (`Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift`),
  regenerated from `contract/conformance/error-catalog.json` via
  `scripts/generate-error-codes.mjs`.
- `AuditHash`, a hand-written HMAC-SHA256 canonicalization
  (`Sources/DPDPGuardConsent/AuditHash.swift`) matching the audit-trail hash
  algorithm in `contract/conformance/audit-hash-spec.md`, verified against
  all 4 golden vectors in `audit-hash-vectors.json`.
- `contract/` — vendored mirror of `@dpdpguard/contract`'s `openapi/v1.yaml`
  and `conformance/*`, pinned via `contract/CONTRACT_VERSION` and refreshed
  with `scripts/update-contract.sh`.
- GitHub Actions CI (`.github/workflows/ci.yml`): builds, tests, and fails
  if `ApiErrorCode.swift` drifts from `error-catalog.json` without being
  regenerated.
- GitHub Actions publish workflow (`.github/workflows/publish.yml`):
  triggered by semver tag pushes, re-verifies build/test at the tagged
  commit, then cuts a GitHub Release.

### Known limitations

- The generated client skips `getNomination`'s `200` response body: its
  schema is typed `null` in the OpenAPI spec, which
  `swift-openapi-generator` cannot represent. Needs a real schema upstream
  in `@dpdpguard/contract` before that endpoint's response is usable from
  the generated client.
- DSR, grievance, and nomination endpoints are present in the OpenAPI spec
  but not yet exercised by any SDK-level tests here.

[0.1.0]: https://github.com/dpdp-guard-ai/dpdpguard-ios-sdk/releases/tag/0.1.0
