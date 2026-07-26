# dpdpguard-ios-sdk

DPDP Guard iOS SDK (Swift) - native consent banner, on-device gating, offline durability

Package: `DPDPGuardConsent`

Part of the DPDP Guard SDK family. See the design spec:
https://github.com/chintans/dpdpbot/blob/main/docs/specs/mobile-server-sdk.md

## Installation

Add this repo's URL in Xcode (File → Add Package Dependencies) or in your
own `Package.swift`:

```swift
.package(url: "https://github.com/dpdp-guard-ai/dpdpguard-ios-sdk.git", from: "0.1.0")
```

Then add `DPDPGuardConsent` as a dependency of your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "DPDPGuardConsent", package: "dpdpguard-ios-sdk")
    ]
)
```

## Usage

### Creating a client

Every `/api/v1` and `/cm/v1/consent` operation requires a bearer token —
either a per-organization API key, a brokered Data Principal access token,
or a staff JWT (see [Authentication](#authentication) below). Attach it with
a `ClientMiddleware` so every generated call carries it automatically:

```swift
import DPDPGuardConsent
import DPDPGuardConsentAPI
import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

struct BearerTokenMiddleware: ClientMiddleware {
    let token: @Sendable () async -> String?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        if let token = await token() {
            request.headerFields[.authorization] = "Bearer \(token)"
        }
        return try await next(request, body, baseURL)
    }
}

let client = Client(
    serverURL: URL(string: "https://your-deployment.convex.site")!,
    transport: URLSessionTransport(),
    middlewares: [BearerTokenMiddleware(token: { await TokenStore.shared.currentToken })]
)
```

### Fetching banner config

```swift
let response = try await client.getBannerConfig(
    .init(path: .init(orgId: "org_abc123"))
)

switch response {
case .ok(let ok):
    let config = try ok.body.json
    print("banner config version:", config.configVersion)
case .notFound:
    print("organization not found")
case .undocumented(let statusCode, _):
    print("unexpected status:", statusCode)
}
```

Every generated operation follows this shape: call it with a typed `Input`,
then `switch` on the typed `Output` to handle each documented response
status (see `Sources/DPDPGuardConsentAPI/openapi.yaml` — mirrored from
`contract/openapi/v1.yaml` — for the full list of operations, e.g.
`getConsent`, `withdrawConsent`, `getOrgBySlug`, `getNoticesForOrg`,
`brokerToken`, `giveConsentAnonymous`, `createDsrRequest`, `createGrievance`).

### Recording consent

```swift
let response = try await client.recordConsent(
    .init(body: .json(.init(
        email: "user@example.com",
        noticeId: "notice_v1",
        purpose: "Newsletter",
        dataTypes: ["email"]
    )))
)

switch response {
case .created(let created):
    let record = try created.body.json
    print("consent recorded:", record)
case .forbidden:
    print("blocked - e.g. tracking consent for a verified minor")
case .undocumented(let statusCode, _):
    print("unexpected status:", statusCode)
default:
    break
}
```

> **Note:** `recordConsent`/`getConsent`/`withdrawConsent` are the older
> `/cm/v1/consent` slice, whose error responses use the free-text-only
> `Error` shape (no machine-readable `code` yet). The typed `ApiError` below
> is used by the `/api/v1` operations (`getBannerConfig`, `getOrgBySlug`,
> `brokerToken`, `giveConsentAnonymous`, etc.).

### Handling `/api/v1` errors

`/api/v1` error responses decode to `Components.Schemas.ApiError`, whose
`code` field is one of the generated `ApiErrorCode` cases
(`Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift`, kept in sync with
`contract/conformance/error-catalog.json`):

```swift
let response = try await client.getBannerConfig(.init(path: .init(orgId: "org_abc123")))

switch response {
case .notFound(let notFound):
    let apiError = try notFound.body.json
    if let code = ApiErrorCode(rawValue: apiError.code) {
        switch code {
        case .sdkVersionUnsupported:
            // prompt the user to update the app
            break
        case .rateLimited:
            // back off and retry
            break
        default:
            break
        }
    }
default:
    break
}
```

### Computing an audit hash

If you need to verify a consent event's `auditHash` client-side (e.g. to
detect tampering before displaying a consent record), use `computeAuditHash`
— it implements the same HMAC-SHA256 canonicalization documented in
`contract/conformance/audit-hash-spec.md`, byte-for-byte identical across
every DPDP Guard SDK:

```swift
let input = AuditHashInput(
    organizationId: "org_abc123",
    noticeId: "notice_v1",
    noticeVersion: 1,
    purpose: "Newsletter",
    dataTypes: ["email"],
    givenAt: 1_700_000_000_000,
    source: .direct
)

let hash = try computeAuditHash(input, secret: hmacSecret)
```

`secret` must be the platform's real `DPDP_AUDIT_HASH_HMAC_SECRET` value in
production — `computeAuditHash` throws `AuditHashError.missingSecret` rather
than silently falling back to an unkeyed hash if you pass an empty string.

### Authentication

The OpenAPI spec documents three bearer schemes (see
`contract/openapi/v1.yaml`'s `securitySchemes`) — pick whichever matches
your integration:

| Scheme | How to obtain it | Typical caller |
| --- | --- | --- |
| `apiKey` | Minted per-organization via the Consent Manager dashboard | Server-to-server / trusted native code, `/cm/v1/consent` |
| `principalToken` | `POST /api/v1/auth/broker-token` (short-lived, no refresh token) | End-user app, most `/api/v1` reads/writes |
| `staffToken` | Convex Auth JWT from a fiduciary/DPO staff login | Internal staff tooling |

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

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs on every
push to `master` and every PR: builds, tests, and fails if
`ApiErrorCode.swift` has drifted from `error-catalog.json` without being
regenerated.

Publishing is git-tag based — Swift Package Manager resolves packages
directly from git, there is no separate registry push. Pushing a semver tag
(`\d+.\d+.\d+`, no `v` prefix) triggers
[`.github/workflows/publish.yml`](.github/workflows/publish.yml), which
builds and tests at that tag, then cuts a GitHub Release:

```bash
git tag 1.0.0
git push origin 1.0.0
```

See [`CHANGELOG.md`](CHANGELOG.md) for release history.
