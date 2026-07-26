import Foundation

// These types mirror the schemas in `openapi/v1.yaml` (the `dpdpbot` repo's
// source of truth for the `/api/v1` wire shape, ADR-002 D1). They rely on
// Swift's synthesized `Codable` conformance, which ignores unknown JSON keys
// by default — this is the "tolerant reader" behavior ADR-002 D4 requires,
// so do NOT add a custom `init(from:)` that rejects unrecognized fields.

// MARK: - Error body

/// Wire shape of `components/schemas/ApiError`: `{ code, error }`.
public struct ApiErrorBody: Codable, Sendable, Equatable {
    public let code: String
    public let error: String
}

// MARK: - Organization

public struct OrgSummary: Codable, Sendable, Equatable {
    public let orgId: String
    public let name: String
    public let slug: String

    public init(orgId: String, name: String, slug: String) {
        self.orgId = orgId
        self.name = name
        self.slug = slug
    }
}

// MARK: - Notice

public enum NoticeStatus: String, Codable, Sendable {
    case draft
    case published
}

public struct NoticeItem: Codable, Sendable, Equatable {
    public let purpose: String
    public let personalDataDescription: String

    public init(purpose: String, personalDataDescription: String) {
        self.purpose = purpose
        self.personalDataDescription = personalDataDescription
    }
}

/// One language entry of `Notice.content` (a map of language code to
/// `{ title, body }`).
public struct NoticeContentEntry: Codable, Sendable, Equatable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct Notice: Codable, Sendable, Equatable {
    public let id: String
    public let organizationId: String
    public let version: Int
    public let itemized: [NoticeItem]
    /// Map of language code (e.g. `"en"`) to `{ title, body }`.
    public let content: [String: NoticeContentEntry]
    public let status: NoticeStatus

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case organizationId
        case version
        case itemized
        case content
        case status
    }

    public init(
        id: String,
        organizationId: String,
        version: Int,
        itemized: [NoticeItem],
        content: [String: NoticeContentEntry],
        status: NoticeStatus
    ) {
        self.id = id
        self.organizationId = organizationId
        self.version = version
        self.itemized = itemized
        self.content = content
        self.status = status
    }
}

public struct NoticesResponse: Codable, Sendable, Equatable {
    public let notices: [Notice]
}

// MARK: - Banner config

public struct BannerConfigResponse: Codable, Sendable, Equatable {
    /// Free-form presentation settings — the OpenAPI contract documents this
    /// only as `type: object` with no fixed shape (ADR-006 D2).
    public let bannerSettings: [String: JSONValue]?
    /// A presentation-config version (ADR-006 D3), distinct from
    /// `Notice.version` — a cosmetic edit bumps it without ever triggering
    /// re-consent.
    public let configVersion: Int
}

// MARK: - Auth / broker token (ADR-004 D1/D2)

public struct BrokerTokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Int
    public let tokenType: String
}

struct BrokerTokenRequestBody: Encodable, Sendable {
    let externalId: String
}

// MARK: - Link anonymous consent (ADR-004 D3)

public struct NeedsReconsentItem: Codable, Sendable, Equatable {
    public let noticeId: String
    public let purpose: String
}

public struct LinkAnonymousConsentResponse: Codable, Sendable, Equatable {
    public let linkedCount: Int
    public let needsReconsent: [NeedsReconsentItem]
}

struct LinkAnonymousConsentRequestBody: Encodable, Sendable {
    let anonymousId: String
}

// MARK: - DSR (spec §4.2)

public enum DsrRequestType: String, Codable, Sendable {
    case summary
    case processors
    case correction
    case erasure
}

public enum DsrRequestStatus: String, Codable, Sendable {
    case pending
    case inProgress = "in_progress"
    case completed
    case rejected
}

public struct DsrRequest: Codable, Sendable, Equatable {
    public let requestId: String
    public let type: DsrRequestType
    public let status: DsrRequestStatus
    /// SLA deadline, Unix epoch milliseconds.
    public let dueAt: Int?
    public let requestDetails: String?

    public init(
        requestId: String,
        type: DsrRequestType,
        status: DsrRequestStatus,
        dueAt: Int? = nil,
        requestDetails: String? = nil
    ) {
        self.requestId = requestId
        self.type = type
        self.status = status
        self.dueAt = dueAt
        self.requestDetails = requestDetails
    }
}

public struct ListDsrRequestsResponse: Codable, Sendable, Equatable {
    public let requests: [DsrRequest]
}

public struct CreateDsrRequestInput: Encodable, Sendable {
    public let organizationId: String
    public let type: DsrRequestType
    public let details: String?

    public init(organizationId: String, type: DsrRequestType, details: String? = nil) {
        self.organizationId = organizationId
        self.type = type
        self.details = details
    }
}

// MARK: - Grievances (spec §4.2)

public enum GrievanceStatus: String, Codable, Sendable {
    case open
    case inProgress = "in_progress"
    case resolved
}

public struct Grievance: Codable, Sendable, Equatable {
    public let grievanceId: String
    public let subject: String
    public let description: String
    public let status: GrievanceStatus
    /// SLA deadline, Unix epoch milliseconds.
    public let dueAt: Int
    public let respondedAt: Int?
    public let response: String?

    public init(
        grievanceId: String,
        subject: String,
        description: String,
        status: GrievanceStatus,
        dueAt: Int,
        respondedAt: Int? = nil,
        response: String? = nil
    ) {
        self.grievanceId = grievanceId
        self.subject = subject
        self.description = description
        self.status = status
        self.dueAt = dueAt
        self.respondedAt = respondedAt
        self.response = response
    }
}

public struct ListGrievancesResponse: Codable, Sendable, Equatable {
    public let grievances: [Grievance]
}

public struct CreateGrievanceInput: Encodable, Sendable {
    public let organizationId: String
    public let subject: String
    public let description: String

    public init(organizationId: String, subject: String, description: String) {
        self.organizationId = organizationId
        self.subject = subject
        self.description = description
    }
}

// MARK: - Nomination (spec §4.2)

public enum NominationStatus: String, Codable, Sendable {
    case active
    case revoked
}

public struct Nomination: Codable, Sendable, Equatable {
    public let nominationId: String
    public let nomineeName: String
    public let nomineeContact: String
    public let status: NominationStatus

    public init(nominationId: String, nomineeName: String, nomineeContact: String, status: NominationStatus) {
        self.nominationId = nominationId
        self.nomineeName = nomineeName
        self.nomineeContact = nomineeContact
        self.status = status
    }
}

public struct UpsertNominationInput: Encodable, Sendable {
    public let nomineeName: String
    public let nomineeContact: String

    public init(nomineeName: String, nomineeContact: String) {
        self.nomineeName = nomineeName
        self.nomineeContact = nomineeContact
    }
}

public struct RevokeNominationResponse: Codable, Sendable, Equatable {
    public let revoked: Bool
}
