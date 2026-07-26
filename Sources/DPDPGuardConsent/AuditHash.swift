import Crypto
import Foundation

/// ADR-004 D5 auth provenance for a consent event.
public enum AuditHashSource: String, Codable, Sendable {
    case brokered
    case direct
    case anonymous
    case linked
}

/// Input to the audit-hash canonicalization in `contract/conformance/audit-hash-spec.md`.
public struct AuditHashInput: Sendable {
    public var organizationId: String
    public var noticeId: String
    public var noticeVersion: Int
    public var purpose: String
    public var dataTypes: [String]
    /// Unix epoch milliseconds - client-authoritative per ADR-003 D3.
    public var givenAt: Int64
    public var source: AuditHashSource?

    public init(
        organizationId: String,
        noticeId: String,
        noticeVersion: Int,
        purpose: String,
        dataTypes: [String],
        givenAt: Int64,
        source: AuditHashSource?
    ) {
        self.organizationId = organizationId
        self.noticeId = noticeId
        self.noticeVersion = noticeVersion
        self.purpose = purpose
        self.dataTypes = dataTypes
        self.givenAt = givenAt
        self.source = source
    }
}

public enum AuditHashError: Error, Equatable {
    /// `DPDP_AUDIT_HASH_HMAC_SECRET` must be set explicitly - there is no
    /// unkeyed-hash fallback, per audit-hash-spec.md's "Key management".
    case missingSecret
}

/// The `organizationId|noticeId|noticeVersion|purpose|dataTypes|givenAt|source`
/// string, with `dataTypes` sorted lexicographically and joined by `,`, and an
/// absent `source` serialized as the literal `"null"`.
public func canonicalAuditString(_ input: AuditHashInput) -> String {
    let sortedDataTypes = input.dataTypes.sorted().joined(separator: ",")
    let source = input.source?.rawValue ?? "null"
    return [
        input.organizationId,
        input.noticeId,
        String(input.noticeVersion),
        input.purpose,
        sortedDataTypes,
        String(input.givenAt),
        source
    ].joined(separator: "|")
}

/// HMAC-SHA256 of the canonical audit string, hex-encoded lowercase.
public func computeAuditHash(_ input: AuditHashInput, secret: String) throws -> String {
    guard !secret.isEmpty else { throw AuditHashError.missingSecret }
    let key = SymmetricKey(data: Data(secret.utf8))
    let canonical = canonicalAuditString(input)
    let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
    return mac.map { String(format: "%02x", $0) }.joined()
}
