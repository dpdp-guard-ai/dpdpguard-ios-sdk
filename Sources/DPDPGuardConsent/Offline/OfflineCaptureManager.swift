import DPDPGuardConsentAPI
import Foundation
import OpenAPIRuntime

/// Result of syncing one previously-captured session.
public enum OfflineCaptureSyncOutcome: Sendable, Equatable {
    /// The server processed the session (any of `verified` / `quarantined` /
    /// `rejected` - see `docs/specs/offline-consent-capture.md` §4.4). In
    /// every case the session is evicted from local storage: a quarantined
    /// or rejected record is retained server-side as evidence, and the
    /// local copy's only job (surviving until the server has acknowledged
    /// it) is done.
    case acknowledged(clientSessionId: UUID, status: String, consentId: String?, reason: String?, withdrawalToken: String?)
    /// The session was in the batch sent to the server but had no
    /// corresponding entry in the response - should not happen against a
    /// spec-conformant server, but surfaced rather than silently dropped.
    case missingFromResponse(clientSessionId: UUID)

    public var clientSessionId: UUID {
        switch self {
        case .acknowledged(let id, _, _, _, _): return id
        case .missingFromResponse(let id): return id
        }
    }
}

/// The offline-first capture facade
/// (`docs/specs/offline-consent-capture.md` §4, §6.1): notice render and
/// UI are the host app's responsibility (per Non-Goal 5, "we ship an SDK and
/// a reference app; the enterprise ships the app under its own brand"), but
/// this manager owns everything from "the principal made a decision" through
/// "that decision is durably, verifiably recorded":
///
///  1. `capture` builds the Cryptographic Consent Artifact, signs it with
///     the enrolled device identity, and persists it to the encrypted local
///     store - all synchronously and without a network call, so it works at
///     zero bars (Goal 2).
///  2. `syncPending` batches whatever is queued (server caps a batch at 200
///     sessions/call) to `POST /api/v1/offline/captures` and evicts each
///     session the server acknowledges, retrying nothing itself - callers
///     control when/how often sync runs (foreground, background task,
///     connectivity-regained callback, ...).
public final class OfflineCaptureManager: @unchecked Sendable {
    /// The server rejects a batch larger than this - see `syncOfflineCaptures`.
    public static let maxBatchSize = 200

    private let identity: AgentDeviceIdentity
    private let store: OfflineCaptureStore

    public init(identity: AgentDeviceIdentity, store: OfflineCaptureStore) {
        self.identity = identity
        self.store = store
    }

    /// Builds, signs, and locally persists one offline capture session.
    /// Purely local - no network I/O - so it can run with the radio off.
    ///
    /// - Parameters mirror `CaptureArtifactInput` / `offlineCaptureSessions`;
    ///   see their doc comments for what each proves. `capturedAt` defaults
    ///   to "now" but accepts an explicit `Date` since the device clock is
    ///   recorded verbatim, not re-derived at sync time.
    @discardableResult
    public func capture(
        deviceId: String,
        organizationId: String,
        noticeId: String,
        noticeVersion: Int,
        noticeLocale: String,
        purposeGrants: [PurposeGrant],
        dataTypes: [String],
        principalHandle: PrincipalHandle,
        channel: CaptureChannel,
        linkId: String? = nil,
        capturedAt: Date = Date()
    ) throws -> OfflineCaptureSession {
        let clientSessionId = UUID()
        let capturedAtClient = Int64((capturedAt.timeIntervalSince1970 * 1000).rounded())

        let artifactInput = CaptureArtifactInput(
            clientSessionId: clientSessionId,
            organizationId: organizationId,
            deviceId: deviceId,
            noticeId: noticeId,
            noticeVersion: noticeVersion,
            noticeLocale: noticeLocale,
            purposeGrants: purposeGrants,
            dataTypes: dataTypes,
            principalHandle: principalHandle,
            capturedAtClient: capturedAtClient,
            channel: channel
        )
        let signatureBase64 = try identity.sign(canonicalBytes: CaptureArtifact.canonicalBytes(for: artifactInput))

        let session = OfflineCaptureSession(
            clientSessionId: clientSessionId,
            organizationId: organizationId,
            deviceId: deviceId,
            noticeId: noticeId,
            noticeVersion: noticeVersion,
            noticeLocale: noticeLocale,
            channel: channel,
            capturedAtClient: capturedAtClient,
            deviceSignatureBase64: signatureBase64,
            dataTypes: dataTypes,
            purposeGrants: purposeGrants,
            principalHandle: principalHandle,
            linkId: linkId
        )
        try store.save(session)
        return session
    }

    /// Every session currently queued locally, waiting for `syncPending`.
    public func pendingSessions() throws -> [OfflineCaptureSession] {
        try store.loadPending()
    }

    /// Sends up to `maxBatchSize` pending sessions to
    /// `POST /api/v1/offline/captures` and evicts every session the server
    /// acknowledges (any terminal status - §4.4's "partial batch success is
    /// normal" applies here too: one quarantined session in the batch does
    /// not stop the others from being evicted or block the next call).
    ///
    /// Sessions beyond `maxBatchSize` are left queued for a subsequent call
    /// - callers syncing a large backlog should call this in a loop until
    /// `pendingSessions()` is empty or unchanged.
    ///
    /// Throws only for a transport/decoding failure covering the whole
    /// batch; per-session outcomes are always returned, never thrown.
    public func syncPending(using client: Client) async throws -> [OfflineCaptureSyncOutcome] {
        let pending = Array(try store.loadPending().prefix(Self.maxBatchSize))
        guard !pending.isEmpty else { return [] }

        let payload = pending.map(Self.requestPayload)
        let response = try await client.syncOfflineCaptures(.init(body: .json(.init(sessions: payload))))

        // `results`' element type is left to inference rather than spelled
        // out here - swift-openapi-generator's exact nested-type name for an
        // inline (non-$ref) array-of-objects response property could not be
        // confirmed against a real `swift build` in the environment this was
        // written in (see the NOTE on `requestPayload` below), so this
        // function is written to need zero knowledge of that spelling.
        switch response {
        case .ok(let ok):
            let results = try ok.body.json.results
            let byId = Dictionary(uniqueKeysWithValues: results.map { ($0.clientSessionId, $0) })

            var outcomes: [OfflineCaptureSyncOutcome] = []
            outcomes.reserveCapacity(pending.count)
            for session in pending {
                let idString = session.clientSessionId.uuidString.lowercased()
                guard let result = byId[idString] else {
                    outcomes.append(.missingFromResponse(clientSessionId: session.clientSessionId))
                    continue
                }
                try store.remove(clientSessionId: session.clientSessionId)
                outcomes.append(.acknowledged(
                    clientSessionId: session.clientSessionId,
                    status: result.status.rawValue,
                    consentId: result.consentId,
                    reason: result.reason,
                    withdrawalToken: result.withdrawalToken
                ))
            }
            return outcomes
        case .undocumented(let statusCode, _):
            throw OfflineCaptureManagerError.unexpectedStatus(statusCode)
        default:
            // badRequest / unauthorized / notFound / tooManyRequests: all
            // documented failure responses for the whole batch (malformed
            // body, bad/revoked API key, flag off, rate limit) - none is
            // per-session, so there is nothing to partially apply.
            throw OfflineCaptureManagerError.requestRejected
        }
    }

    // MARK: - Private

    /// Maps a locally-persisted session to the generated request schema.
    ///
    /// The nested enum/object type names spelled out below
    /// (`ChannelPayload`, `PurposeGrantsPayloadPayload`,
    /// `PrincipalHandlePayload`, and their own nested `CategoryPayload` /
    /// `StatusPayload` / `KindPayload`) follow `swift-openapi-generator`'s
    /// documented synthesized-name convention for inline (non-`$ref`)
    /// schemas: `<PropertyName>Payload` for a scalar/object property, with
    /// an extra `Payload` suffix for the item type of an array property.
    /// This could **not** be confirmed against a real `swift build` in the
    /// environment this was written in (Windows, no Developer Mode enabled -
    /// see CHANGELOG); if CI reports a different spelling, this is the one
    /// function that needs adjusting - nothing else in `Offline/` depends on
    /// generated types.
    ///
    /// Field construction is split into several narrow statements rather
    /// than one combined literal deliberately: an earlier version built
    /// every field - including two levels of nested `.init`/`??`/`.map` - as
    /// a single expression, and CI's type checker timed out on it ("unable
    /// to type-check this expression in reasonable time").
    private static func requestPayload(for session: OfflineCaptureSession) -> Components.Schemas.OfflineCaptureSession {
        let channel = Components.Schemas.OfflineCaptureSession.ChannelPayload(rawValue: session.channel.rawValue) ?? .agentApp

        let purposeGrants: [Components.Schemas.OfflineCaptureSession.PurposeGrantsPayloadPayload] = session.purposeGrants.map { grant in
            let category = Components.Schemas.OfflineCaptureSession.PurposeGrantsPayloadPayload
                .CategoryPayload(rawValue: grant.category.rawValue) ?? .essential
            let status = Components.Schemas.OfflineCaptureSession.PurposeGrantsPayloadPayload
                .StatusPayload(rawValue: grant.status.rawValue) ?? .optIn
            return .init(purposeKey: grant.purposeKey, purposeLabel: grant.purposeLabel, category: category, status: status)
        }

        let principalHandleKind = Components.Schemas.OfflineCaptureSession.PrincipalHandlePayload
            .KindPayload(rawValue: session.principalHandle.kind.rawValue) ?? .none
        let principalHandle = Components.Schemas.OfflineCaptureSession.PrincipalHandlePayload(
            kind: principalHandleKind,
            value: session.principalHandle.value
        )

        return Components.Schemas.OfflineCaptureSession(
            clientSessionId: session.clientSessionId.uuidString.lowercased(),
            deviceId: session.deviceId,
            noticeId: session.noticeId,
            noticeVersion: Double(session.noticeVersion),
            noticeLocale: session.noticeLocale,
            channel: channel,
            capturedAtClient: Double(session.capturedAtClient),
            deviceSignature: session.deviceSignatureBase64,
            dataTypes: session.dataTypes,
            purposeGrants: purposeGrants,
            principalHandle: principalHandle,
            linkId: session.linkId
        )
    }
}

public enum OfflineCaptureManagerError: Error, Equatable {
    case unexpectedStatus(Int)
    /// One of `syncOfflineCaptures`'s documented non-`200` responses
    /// (`badRequest` / `unauthorized` / `notFound` / `tooManyRequests`) -
    /// applies to the whole batch, so there are no per-session outcomes to
    /// report for it.
    case requestRejected
}
