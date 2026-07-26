import Foundation

/// ADR-002 D2's typed error-code enum. Mirrors
/// `conformance/error-catalog.json` in the main `dpdpbot` repo 1:1 — that
/// file documents these 10 codes as the stable, machine-readable contract
/// for every non-2xx `/api/v1` response. Adding a code is additive (minor);
/// changing an existing code's meaning is breaking (major) under ADR-002 D4.
public enum ApiErrorCode: String, Codable, Sendable, CaseIterable {
    case minorTrackingBlocked = "MINOR_TRACKING_BLOCKED"
    case noticeNotPublished = "NOTICE_NOT_PUBLISHED"
    case alreadyConsented = "ALREADY_CONSENTED"
    case notAssociatedWithOrg = "NOT_ASSOCIATED_WITH_ORG"
    case invalidStatusTransition = "INVALID_STATUS_TRANSITION"
    case sdkVersionUnsupported = "SDK_VERSION_UNSUPPORTED"
    case notFound = "NOT_FOUND"
    case unauthorized = "UNAUTHORIZED"
    case rateLimited = "RATE_LIMITED"
    case validationError = "VALIDATION_ERROR"
}

/// One entry of the machine-readable error catalog: a stable `code` plus a
/// human-readable `description`.
public struct ErrorCatalogEntry: Codable, Sendable, Equatable {
    public let code: String
    public let description: String

    public init(code: String, description: String) {
        self.code = code
        self.description = description
    }
}

/// The full error catalog, embedded verbatim from
/// `conformance/error-catalog.json` (ADR-002 D2). Kept as a Swift literal
/// (rather than loaded from a bundled JSON resource) to keep the dependency
/// surface small; if the catalog ever drifts, update this list to match the
/// source-of-truth JSON file.
public let errorCatalog: [ErrorCatalogEntry] = [
    ErrorCatalogEntry(
        code: "MINOR_TRACKING_BLOCKED",
        description: "Tracking/analytics consent is disabled for a verified minor and cannot be granted."
    ),
    ErrorCatalogEntry(
        code: "NOTICE_NOT_PUBLISHED",
        description: "The referenced notice exists but is not in a published state."
    ),
    ErrorCatalogEntry(
        code: "ALREADY_CONSENTED",
        description: "A consent decision already exists for this (user, notice, purpose) and the request would duplicate it."
    ),
    ErrorCatalogEntry(
        code: "NOT_ASSOCIATED_WITH_ORG",
        description: "The authenticated principal does not belong to the organization the request targets."
    ),
    ErrorCatalogEntry(
        code: "INVALID_STATUS_TRANSITION",
        description: "The requested status change is not a valid transition from the resource's current status."
    ),
    ErrorCatalogEntry(
        code: "SDK_VERSION_UNSUPPORTED",
        description: "The calling SDK's version is below the server's configured minimum-supported floor (ADR-002 D6)."
    ),
    ErrorCatalogEntry(
        code: "NOT_FOUND",
        description: "The requested resource does not exist or is not visible to the authenticated principal."
    ),
    ErrorCatalogEntry(
        code: "UNAUTHORIZED",
        description: "The request is missing valid authentication or the credential does not grant access to this resource."
    ),
    ErrorCatalogEntry(
        code: "RATE_LIMITED",
        description: "The request was rejected because the caller exceeded a rate limit."
    ),
    ErrorCatalogEntry(
        code: "VALIDATION_ERROR",
        description: "The request failed validation and no more specific code applies; the human-readable error message has details."
    )
]

/// Thrown by ``DPDPGuardClient`` for any non-2xx `/api/v1` response. `code`
/// is kept as a raw `String` (rather than `ApiErrorCode` directly) so that a
/// server-added code the SDK doesn't know about yet still surfaces instead
/// of being lost — use ``knownCode`` to get a typed value when it matches
/// one of the catalog's current cases.
public struct DPDPGuardApiError: Error, Sendable, Equatable, CustomStringConvertible {
    public let code: String
    public let message: String
    public let status: Int

    public init(code: String, message: String, status: Int) {
        self.code = code
        self.message = message
        self.status = status
    }

    /// The strongly-typed error code, or `nil` if the server returned a
    /// code this version of the SDK doesn't recognize yet.
    public var knownCode: ApiErrorCode? {
        ApiErrorCode(rawValue: code)
    }

    public var description: String {
        "DPDPGuardApiError(code: \(code), status: \(status)): \(message)"
    }
}
