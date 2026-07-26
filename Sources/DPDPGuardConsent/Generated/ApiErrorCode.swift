// Generated from contract/conformance/error-catalog.json by
// scripts/generate-error-codes.mjs. Do not hand-edit - re-run the script
// against an updated @dpdpguard/contract and commit the diff instead.

/// The ADR-002 D2 machine-readable `ApiError.code` catalog.
public enum ApiErrorCode: String, Codable, Sendable, CaseIterable {
    /// Tracking/analytics consent is disabled for a verified minor and cannot be granted.
    case minorTrackingBlocked = "MINOR_TRACKING_BLOCKED"

    /// The referenced notice exists but is not in a published state.
    case noticeNotPublished = "NOTICE_NOT_PUBLISHED"

    /// A consent decision already exists for this (user, notice, purpose) and the request would duplicate it.
    case alreadyConsented = "ALREADY_CONSENTED"

    /// The authenticated principal does not belong to the organization the request targets.
    case notAssociatedWithOrg = "NOT_ASSOCIATED_WITH_ORG"

    /// The requested status change is not a valid transition from the resource's current status.
    case invalidStatusTransition = "INVALID_STATUS_TRANSITION"

    /// The calling SDK's version is below the server's configured minimum-supported floor (ADR-002 D6).
    case sdkVersionUnsupported = "SDK_VERSION_UNSUPPORTED"

    /// The requested resource does not exist or is not visible to the authenticated principal.
    case notFound = "NOT_FOUND"

    /// The request is missing valid authentication or the credential does not grant access to this resource.
    case unauthorized = "UNAUTHORIZED"

    /// The request was rejected because the caller exceeded a rate limit.
    case rateLimited = "RATE_LIMITED"

    /// The request failed validation and no more specific code applies; the human-readable error message has details.
    case validationError = "VALIDATION_ERROR"
}
