import Crypto
import Foundation

/// The channel a capture session originated from - `offlineCaptureSessions.channel`.
public enum CaptureChannel: String, Codable, Sendable {
    case qr
    case agentApp = "agent_app"
    case pos
    case asyncLink = "async_link"
    case ivr
}

/// `consentPurposeGrants.category`.
public enum PurposeCategory: String, Codable, Sendable {
    case essential
    case nonEssential = "non_essential"
}

/// `consentPurposeGrants.status`.
public enum PurposeGrantStatus: String, Codable, Sendable {
    case optIn = "opt_in"
    case optOut = "opt_out"
}

/// One purpose the principal was shown and decided on. Declined purposes are
/// carried too - proving someone was shown a purpose and refused is what the
/// artifact is for (conformance/audit-hash-spec.md's "separator injection" vectors
/// exist precisely because two structurally different grant sets must never
/// canonicalize to the same bytes).
public struct PurposeGrant: Codable, Equatable, Sendable {
    public var purposeKey: String
    public var purposeLabel: String
    public var category: PurposeCategory
    public var status: PurposeGrantStatus

    public init(purposeKey: String, purposeLabel: String, category: PurposeCategory, status: PurposeGrantStatus) {
        self.purposeKey = purposeKey
        self.purposeLabel = purposeLabel
        self.category = category
        self.status = status
    }
}

/// `offlineCaptureSessions.principalHandle.kind`.
public enum PrincipalHandleKind: String, Codable, Sendable {
    case phoneHash = "phone_hash"
    case uhid
    case cbsRef = "cbs_ref"
    case none
}

/// The identity handle a principal can later withdraw by. Signed **raw** - the
/// server HMACs `phone_hash` values per-organization; the raw number is never
/// persisted server-side, only inside this locally-held, encrypted-at-rest
/// session pending sync (see `OfflineCaptureStore`).
public struct PrincipalHandle: Codable, Equatable, Sendable {
    public var kind: PrincipalHandleKind
    public var value: String

    public init(kind: PrincipalHandleKind, value: String) {
        self.kind = kind
        self.value = value
    }

    /// A capture where the principal declined to leave any handle (permitted,
    /// but surfaced as unwithdrawable and penalized in the org's compliance score).
    public static let none = PrincipalHandle(kind: .none, value: "")
}

/// Everything the Cryptographic Consent Artifact canonicalization
/// (`conformance/audit-hash-spec.md`, `docs/specs/offline-consent-capture.md`
/// §4.2) signs over. This is a pure value type, deliberately decoupled from
/// the generated `DPDPGuardConsentAPI` request/response types so the
/// canonicalization logic - the part that must be byte-for-byte identical to
/// every other DPDP Guard SDK - has no generated-code dependency at all.
public struct CaptureArtifactInput: Sendable {
    public var clientSessionId: UUID
    public var organizationId: String
    public var deviceId: String
    public var noticeId: String
    public var noticeVersion: Int
    public var noticeLocale: String
    public var purposeGrants: [PurposeGrant]
    public var dataTypes: [String]
    public var principalHandle: PrincipalHandle
    /// Device clock at capture, Unix epoch milliseconds. Context, never
    /// authority - see §4.3. Recorded verbatim into the signed payload.
    public var capturedAtClient: Int64
    public var channel: CaptureChannel

    public init(
        clientSessionId: UUID,
        organizationId: String,
        deviceId: String,
        noticeId: String,
        noticeVersion: Int,
        noticeLocale: String,
        purposeGrants: [PurposeGrant],
        dataTypes: [String],
        principalHandle: PrincipalHandle,
        capturedAtClient: Int64,
        channel: CaptureChannel
    ) {
        self.clientSessionId = clientSessionId
        self.organizationId = organizationId
        self.deviceId = deviceId
        self.noticeId = noticeId
        self.noticeVersion = noticeVersion
        self.noticeLocale = noticeLocale
        self.purposeGrants = purposeGrants
        self.dataTypes = dataTypes
        self.principalHandle = principalHandle
        self.capturedAtClient = capturedAtClient
        self.channel = channel
    }
}

/// The Cryptographic Consent Artifact canonicalization, `dpdpcca/2`
/// (`conformance/audit-hash-spec.md`). Deliberately a **second** algorithm
/// from `computeAuditHash`, not a replacement: this proves which enrolled
/// device produced this exact payload, signed with a key that never leaves
/// the device's secure element (`AgentDeviceIdentity`); the HMAC audit hash
/// proves the platform wrote the row and it is unaltered. A DPBI defence
/// needs both.
///
/// Altering this encoding is a breaking change under ADR-002 D4 and
/// invalidates every stored signature - do not modify without bumping
/// `version` and DPO sign-off, exactly as for the audit-hash algorithm.
public enum CaptureArtifact {
    /// The first token of every canonical string. Bumped from `dpdpcca/1`
    /// because unframed, comma-joined lists let a client-supplied
    /// `purposeKey` forge separator collisions (see the "separator
    /// injection" golden vectors) - never revert to bare joins.
    public static let version = "dpdpcca/2"

    /// `<utf8ByteLength>:<value>`. Length is counted in UTF-8 **bytes**, not
    /// characters or UTF-16 units - a Devanagari purpose label is a golden
    /// vector precisely because this is where a naive Swift implementation
    /// (which counts `String.count` in grapheme clusters) would drift.
    private static func frame(_ value: String) -> String {
        "\(value.utf8.count):\(value)"
    }

    /// Byte-wise UTF-8 sort, **not** Swift's default `String` comparison
    /// (which compares Unicode grapheme clusters and would disagree with
    /// every other DPDP Guard SDK on non-ASCII input). `lexicographicallyPrecedes`
    /// over the raw `UTF8View` is the correct, load-bearing comparison here.
    private static func utf8Precedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    /// The exact `dpdpcca/2` canonical string for `input`. Reproduces
    /// `expectedCanonical` in `conformance/capture-artifact-vectors.json`
    /// byte-for-byte; see `CaptureArtifactConformanceTests`.
    public static func canonicalString(for input: CaptureArtifactInput) -> String {
        var tokens: [String] = []
        tokens.reserveCapacity(11 + input.purposeGrants.count * 2 + input.dataTypes.count)

        tokens.append(frame(version))
        tokens.append(frame(input.clientSessionId.uuidString.lowercased()))
        tokens.append(frame(input.organizationId))
        tokens.append(frame(input.deviceId))
        tokens.append(frame(input.noticeId))
        tokens.append(frame(String(input.noticeVersion)))
        tokens.append(frame(input.noticeLocale))

        let sortedGrants = input.purposeGrants.sorted { utf8Precedes($0.purposeKey, $1.purposeKey) }
        tokens.append(frame(String(sortedGrants.count)))
        for grant in sortedGrants {
            tokens.append(frame(grant.purposeKey))
            tokens.append(frame(grant.status.rawValue))
        }

        let sortedDataTypes = input.dataTypes.sorted(by: utf8Precedes)
        tokens.append(frame(String(sortedDataTypes.count)))
        for dataType in sortedDataTypes {
            tokens.append(frame(dataType))
        }

        tokens.append(frame(input.principalHandle.kind.rawValue))
        tokens.append(frame(input.principalHandle.value.isEmpty ? "null" : input.principalHandle.value))
        tokens.append(frame(String(input.capturedAtClient)))
        tokens.append(frame(input.channel.rawValue))

        return tokens.joined(separator: "|")
    }

    /// UTF-8 bytes of `canonicalString(for:)` - what actually gets SHA-256'd
    /// and signed. Exposed separately so `AgentDeviceIdentity.sign` never has
    /// to re-derive UTF-8 encoding rules itself.
    public static func canonicalBytes(for input: CaptureArtifactInput) -> [UInt8] {
        Array(canonicalString(for: input).utf8)
    }
}
