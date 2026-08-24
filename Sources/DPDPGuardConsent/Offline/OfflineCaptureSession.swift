import Foundation

/// A signed, locally-persisted offline capture, waiting to be synced via
/// `POST /api/v1/offline/captures`. Mirrors the `offlineCaptureSessions`
/// fields relevant to the client - see `docs/specs/offline-consent-capture.md`
/// §2.2 for the full server-side row shape.
///
/// This type is deliberately independent of the generated
/// `DPDPGuardConsentAPI` request/response types: it is what `OfflineCaptureStore`
/// persists (encrypted, on-device) and it is immutable/append-only by
/// construction, matching the spec's "capture sessions are immutable,
/// append-only, and uniquely keyed" invariant (§4.4) - nothing in this SDK
/// mutates a session after `OfflineCaptureManager.capture` produces it.
public struct OfflineCaptureSession: Codable, Equatable, Sendable {
    /// Client-generated UUIDv4 and the sync idempotency key. A retried sync
    /// of the same session is a no-op server-side, never a duplicate consent.
    public let clientSessionId: UUID
    /// Retained locally for re-canonicalization (e.g. signature
    /// re-verification before sync) - not part of the wire request body,
    /// since the server derives the organization from the API key.
    public let organizationId: String
    public let deviceId: String
    public let noticeId: String
    public let noticeVersion: Int
    public let noticeLocale: String
    public let channel: CaptureChannel
    /// Device clock at capture, Unix epoch milliseconds. Recorded verbatim -
    /// never used for local arithmetic, see `CaptureArtifactInput.capturedAtClient`.
    public let capturedAtClient: Int64
    /// base64 IEEE-P1363 `r||s` ECDSA P-256 signature over
    /// `CaptureArtifact.canonicalBytes(for:)`, produced at capture time by
    /// `AgentDeviceIdentity.sign(canonicalBytes:)`.
    public let deviceSignatureBase64: String
    public let dataTypes: [String]
    public let purposeGrants: [PurposeGrant]
    public let principalHandle: PrincipalHandle
    /// Set only for QR-originated captures.
    public let linkId: String?

    public init(
        clientSessionId: UUID,
        organizationId: String,
        deviceId: String,
        noticeId: String,
        noticeVersion: Int,
        noticeLocale: String,
        channel: CaptureChannel,
        capturedAtClient: Int64,
        deviceSignatureBase64: String,
        dataTypes: [String],
        purposeGrants: [PurposeGrant],
        principalHandle: PrincipalHandle,
        linkId: String? = nil
    ) {
        self.clientSessionId = clientSessionId
        self.organizationId = organizationId
        self.deviceId = deviceId
        self.noticeId = noticeId
        self.noticeVersion = noticeVersion
        self.noticeLocale = noticeLocale
        self.channel = channel
        self.capturedAtClient = capturedAtClient
        self.deviceSignatureBase64 = deviceSignatureBase64
        self.dataTypes = dataTypes
        self.purposeGrants = purposeGrants
        self.principalHandle = principalHandle
        self.linkId = linkId
    }
}
