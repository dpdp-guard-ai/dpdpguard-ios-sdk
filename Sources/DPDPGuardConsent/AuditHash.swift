import CryptoKit
import Foundation

/// ADR-004 D5 auth provenance for a consent-audit event.
public enum ConsentSource: String, Codable, Sendable {
    case brokered
    case direct
    case anonymous
    case linked
}

/// Input to the audit-hash canonicalization, mirroring
/// `convex/lib/auditHash.ts`'s `AuditHashInput` and pinned by the golden
/// vectors in `conformance/audit-hash-vectors.json` (ADR-002 D5).
public struct AuditHashInput: Sendable, Equatable {
    public let organizationId: String
    public let noticeId: String
    /// The version of the specific notice row consented to, not necessarily
    /// the org's current notice version.
    public let noticeVersion: Int
    public let purpose: String
    /// Sorted lexicographically before hashing — client-side ordering must
    /// not change the hash of an otherwise-identical event.
    public let dataTypes: [String]
    /// Unix epoch milliseconds. Client-authoritative per ADR-003 D3.
    public let givenAt: Int
    public let source: ConsentSource?

    public init(
        organizationId: String,
        noticeId: String,
        noticeVersion: Int,
        purpose: String,
        dataTypes: [String],
        givenAt: Int,
        source: ConsentSource?
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

/// Fixed, versioned canonicalization for the `consentAuditTrail.auditHash`
/// field (`conformance/audit-hash-spec.md`). Any change to this
/// canonicalization or to the hash algorithm is a **major** contract-artifact
/// version bump under ADR-002 D4 and requires a fresh DPO sign-off — see the
/// spec before touching anything in this file.
public enum AuditHash {
    /// Builds the canonical `|`-joined string for `input`. Every field
    /// position is always present, never omitted — a missing field and an
    /// explicit `null` must hash differently from "the field doesn't exist
    /// in this version of the algorithm", so an absent `source` becomes the
    /// literal string `"null"` rather than being skipped.
    public static func canonicalize(_ input: AuditHashInput) -> String {
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

    /// `HMAC-SHA256(canonicalize(input), secret)`, hex-encoded lowercase.
    public static func compute(_ input: AuditHashInput, secret: String) -> String {
        let canonical = canonicalize(input)
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(canonical.utf8), using: key)
        return hexEncodedString(Data(mac))
    }

    /// Manual hex encoding (rather than `String(format: "%02x", ...)`) so
    /// there's no format-string specifier to get subtly wrong.
    private static func hexEncodedString(_ data: Data) -> String {
        let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
        var chars = [UInt8]()
        chars.reserveCapacity(data.count * 2)
        for byte in data {
            chars.append(hexDigits[Int(byte >> 4)])
            chars.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: chars, as: UTF8.self)
    }
}
