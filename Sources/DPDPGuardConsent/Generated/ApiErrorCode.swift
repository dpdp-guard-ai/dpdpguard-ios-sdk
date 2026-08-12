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

    /// The agent credential's granted scopes do not cover the requested tool or resource.
    case scopeInsufficient = "SCOPE_INSUFFICIENT"

    /// The requested MCP tool does not exist or is not exposed by the current catalog version.
    case toolNotAvailable = "TOOL_NOT_AVAILABLE"

    /// The organization has disabled agent access; no agent credential for it can authenticate.
    case orgDisabled = "ORG_DISABLED"

    /// The proposed change was accepted into the approval inbox and requires human review before it takes effect.
    case approvalRequired = "APPROVAL_REQUIRED"

    /// The organization's pending-approval inbox is at capacity and cannot accept another proposal.
    case approvalBacklogFull = "APPROVAL_BACKLOG_FULL"

    /// The referenced proposal's TTL has elapsed and it can no longer be approved or rejected.
    case proposalExpired = "PROPOSAL_EXPIRED"

    /// The proposal requires a second reviewer and the acting principal is the sole available reviewer without an acknowledgement.
    case secondReviewerRequired = "SECOND_REVIEWER_REQUIRED"

    /// The referenced proposal has already been approved or rejected and cannot be reviewed again.
    case proposalAlreadyReviewed = "PROPOSAL_ALREADY_REVIEWED"

    /// The requested read would return more data than the agent surface's per-call volume cap allows.
    case dataVolumeExceeded = "DATA_VOLUME_EXCEEDED"

    /// The organization's subscription plan limit for this resource has been reached.
    case planLimitReached = "PLAN_LIMIT_REACHED"

    /// The agent credential attempted a write operation outside its permitted risk class.
    case agentWriteBlocked = "AGENT_WRITE_BLOCKED"
}
