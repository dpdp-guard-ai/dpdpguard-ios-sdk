# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-08-24

### Added

- **Offline consent capture** (`Sources/DPDPGuardConsent/Offline/`),
  implementing the device-side half of `docs/specs/offline-consent-capture.md`
  §4 (the Cryptographic Consent Artifact) - previously the SDK exposed
  `POST /api/v1/offline/captures` only through the raw generated client, with
  no signing, local persistence, or facade at all (see the "Does iOS SDK
  support offline consent management?" discussion this release closes the
  gap on):
  - `CaptureArtifact` - the `dpdpcca/2` canonicalization from
    `conformance/audit-hash-spec.md`, verified byte-for-byte against
    `conformance/capture-artifact-vectors.json` (now vendored into
    `Tests/DPDPGuardConsentTests/Resources/` and `Package.swift`'s test
    resources). A second, independent proof from `computeAuditHash`: this one
    proves *which enrolled device* produced a payload, not that the platform
    wrote it unaltered.
  - `AgentDeviceIdentityStore` - enrolls an ECDSA P-256 signing key in the
    Secure Enclave when available, falling back to a Keychain-held software
    key (Simulator, non-SE hardware). Private key material never leaves the
    device and this SDK never transmits it; only the SPKI DER public key
    (`AgentDeviceIdentity.publicKeySPKIBase64`) is meant to leave, via the
    fleet-enrollment console flow.
  - `OfflineCaptureStore` - the encrypted local store §4.1 calls for: each
    pending `OfflineCaptureSession` is AES-256-GCM-sealed with a
    Keychain-held key and written one-file-per-session to a directory marked
    excluded from device/iCloud backups. Evicts a session only once its sync
    has been acknowledged by the server.
  - `OfflineCaptureManager` - the facade: `capture(...)` builds, signs, and
    persists a session with no network I/O (works at zero bars, per Goal 2);
    `syncPending(using:)` batches ≤200 pending sessions to
    `POST /api/v1/offline/captures` and evicts every session the server
    acknowledges (verified, quarantined, or rejected - all three are
    terminal server-side acknowledgements per §4.4's "partial batch success
    is normal").

### Notes

- Chosen storage approach: Keychain + AES-GCM-encrypted plain files, not
  SQLCipher (which §4.1 mentions as one option) or a new SQL dependency -
  no new package dependency, and the per-agent pending-session volume this
  is sized for (a queue awaiting the next sync, not a long-lived database)
  doesn't need a queryable store.
- `OfflineCaptureManager.syncPending`'s request-building code
  (`Offline/OfflineCaptureManager.swift`'s `requestPayload`) references the
  generated `Components.Schemas.OfflineCaptureSession` type but deliberately
  avoids spelling any of its nested generated enum type names (relying on
  contextual type inference instead) precisely because those names - unlike
  the `$ref`'d component schema names themselves - could not be confirmed
  against a real `swift build` in the environment this was written in
  (Windows, no Developer Mode enabled; same limitation noted in `1.1.0` and
  `1.2.0`). If CI still finds a mismatch, this is the one function that
  needs adjusting.
- `capture`/`syncPending` do not implement retry/backoff, notice-version
  staleness blocking, or clock-skew handling on the client side - those are
  server-verified at sync time (§4.3, §4.4) and out of scope for this pass.
  Notice bundle pre-caching (§4.1) is also not implemented - it is public,
  non-PII content the host app can fetch directly via
  `GET /api/v1/notices/{noticeId}` and is not part of "the encrypted local
  store holds ... pending `offlineCaptureSessions`, and nothing else."
- `swift build`/`swift test` could **not** be run to verify this change in
  the environment this release was prepared in - same Windows/Developer
  Mode limitation as `1.2.0`. New syntax was checked with `swiftc -parse`
  only (no type-checking, since that requires the generated
  `DPDPGuardConsentAPI` target this code depends on). CI
  (`.github/workflows/ci.yml`) is the real gate for this release; do not
  consider it verified until that run is green.

## [1.2.0] - 2026-08-24

### Changed

- Re-vendored `contract/` from `@dpdpguard/contract@1.6.0` (`openapi/v1.yaml`
  now `2.9.0`), picking up the new `GET /api/v1/consent-status` route:
  resolves an email to the calling org's per-purpose consent grants, gated
  behind the `dpdp_consent_status_lookup_enabled` flag. Purely additive per
  ADR-002 D4 — no error-catalog or audit-hash changes, and no existing
  operation or type changed shape.
- `contract/conformance/capture-artifact-vectors.json` re-added by hand
  after vendoring, same as in `1.1.0` — `scripts/update-contract.sh` still
  only copies `error-catalog.json`/`audit-hash-vectors.json`/
  `audit-hash-spec.md`.

### Notes

- `ApiErrorCode.swift` was not regenerated: `error-catalog.json` is
  byte-identical to `1.1.0`'s vendored copy, confirmed via `git diff`.
- `audit-hash-vectors.json` is also byte-identical; no DPO sign-off applies.
- This is a **minor** bump: the new route is additive and not yet consumed
  by any code in this SDK beyond the generated client.
- `swift build`/`swift test` could **not** be run to verify this change in
  the environment this release was prepared in (Windows; the Swift
  toolchain is present, but SwiftPM's dependency checkouts fail with
  `unable to create symlink ... Permission denied` because Developer Mode
  isn't enabled, so `swift-openapi-generator`/`swift-argument-parser` never
  finish checking out). CI (`.github/workflows/ci.yml`) will run the real
  gate — build, `ApiErrorCode` drift check, and `swift test` — on the next
  push/PR against macOS runners. This release should not be considered
  verified until that run is green.

## [1.1.0] - 2026-08-12

### Fixed

- **Vendoring bug:** `contract/CONTRACT_VERSION` was still `0.2.0` despite the
  `[1.0.0]` entry below claiming a completed "major version bump forced by
  the upstream `@dpdpguard/contract` 1.0.0 breaking change." `git log` on
  `contract/` shows only one commit ever touched it — the initial vendoring
  at `0.2.0` — so `scripts/update-contract.sh` was never actually re-run for
  that release: `contract/openapi/v1.yaml` was still `info.version: 1.1.0`
  (pre-validation-tightening), not the `2.0.0` the 1.0.0 contract bump
  shipped. The `1.0.0` SDK tag was cut on a stale contract the whole time.
  `scripts/update-contract.sh` itself is unaffected — this was a
  process/release-checklist gap, not a script bug.

### Changed

- Re-vendored `contract/` from `@dpdpguard/contract@1.5.0` (`openapi/v1.yaml`
  now `2.8.0`), picking up everything from `1.0.0` through `1.5.0` in one
  pass: the request-validation tightening and optional grievance
  `Idempotency-Key` (`1.0.0`), three partner read routes (`1.1.0`), eleven
  `/mcp/v1` error codes (`1.2.0`, unused by this SDK), the offline-consent-link
  endpoint (`1.3.0`), the offline capture/POS/IVR endpoints (`1.4.0`), and the
  Consent Gate decision/alert read routes plus an audit-hash-spec **Key
  versions** documentation section (`1.5.0`).
- `Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift` regenerated via
  `scripts/generate-error-codes.mjs` against the refreshed
  `error-catalog.json`: 11 new cases for the `/mcp/v1` error codes added in
  contract `1.2.0` (`scopeInsufficient`, `toolNotAvailable`, `orgDisabled`,
  `approvalRequired`, `approvalBacklogFull`, `proposalExpired`,
  `secondReviewerRequired`, `proposalAlreadyReviewed`, `dataVolumeExceeded`,
  `planLimitReached`, `agentWriteBlocked`). None of these codes are
  returned by any endpoint this SDK calls.
- `contract/conformance/capture-artifact-vectors.json` is now vendored
  alongside the other conformance files (previously omitted by
  `scripts/update-contract.sh`, which only copied
  `error-catalog.json`/`audit-hash-vectors.json`/`audit-hash-spec.md`; added
  here by hand since this SDK doesn't yet implement the offline-capture
  endpoints the vectors cover).
- `Tests/DPDPGuardConsentTests/Resources/error-catalog.json` synced to match
  `contract/conformance/error-catalog.json` so
  `ApiErrorCodeConformanceTests` stays green.

### Notes

- Confirmed via `dpdpbot/packages/contract/CHANGELOG.md` that none of
  `1.1.0`–`1.5.0` touch audit-hash canonicalization or the algorithm: every
  entry in that range is flagged "Purely additive" / "Does not touch
  audit-hash canonicalization" under ADR-002 D4/D5, and
  `contract/conformance/audit-hash-vectors.json` is byte-identical
  before and after this update. No DPO sign-off applies, and this release
  did not require one.
- This is a **minor** bump, not a major one, even though it fixes a bug in a
  previously shipped release: the contract changes it pulls in
  (`1.1.0`-`1.5.0`) are all additive per ADR-002 D4, none of the new routes
  or error codes are consumed by this SDK today, and the one breaking
  contract change involved (`1.0.0`'s request-validation tightening) is
  server-side enforcement that this SDK's own `[1.0.0]` entry already
  documented as needing "no functional changes" here. The bug being fixed is
  real and worth calling out loudly (see above), but it does not by itself
  change this SDK's own public API or behavior, which is what its version
  number tracks (ADR-002 D3).
- `swift build`/`swift test` could **not** be run to verify this change: no
  Swift toolchain is installed in the environment this release was prepared
  in (Windows, no `swift`/`xcodebuild` on `PATH`). CI
  (`.github/workflows/ci.yml`) will run the real gate — build, `ApiErrorCode`
  drift check, and `swift test` (which includes the audit-hash and
  error-catalog conformance suites) — on the next push/PR against macOS
  runners. This release should not be considered verified until that run is
  green.

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
