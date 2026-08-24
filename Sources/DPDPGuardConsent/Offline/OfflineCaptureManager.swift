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
        }
    }

    // MARK: - Private

    /// Maps a locally-persisted session to the generated request schema.
    /// Deliberately never spells the nested generated enum type names
    /// (`channel`, `category`, `status`, `kind` on
    /// `Components.Schemas.OfflineCaptureSession`) - `.init(rawValue:)` and
    /// each case are resolved by contextual type inference from the
    /// memberwise initializer instead, so this compiles correctly regardless
    /// of exactly what `swift-openapi-generator` names those nested types.
    /// The raw string values (`"agent_app"`, `"opt_in"`, ...) and the
    /// top-level init parameter labels are the only things that must match
    /// `contract/openapi/v1.yaml`'s `OfflineCaptureSession` schema, and both
    /// are copied directly from it. This could not be confirmed against a
    /// real `swift build` in the environment this was written in (Windows,
    /// no Developer Mode enabled - see CHANGELOG); CI is the real gate.
    private static func requestPayload(for session: OfflineCaptureSession) -> Components.Schemas.OfflineCaptureSession {
        .init(
            clientSessionId: session.clientSessionId.uuidString.lowercased(),
            deviceId: session.deviceId,
            noticeId: session.noticeId,
            noticeVersion: Double(session.noticeVersion),
            noticeLocale: session.noticeLocale,
            channel: .init(rawValue: session.channel.rawValue) ?? .agentApp,
            capturedAtClient: Double(session.capturedAtClient),
            deviceSignature: session.deviceSignatureBase64,
            dataTypes: session.dataTypes,
            purposeGrants: session.purposeGrants.map { grant in
                .init(
                    purposeKey: grant.purposeKey,
                    purposeLabel: grant.purposeLabel,
                    category: .init(rawValue: grant.category.rawValue) ?? .essential,
                    status: .init(rawValue: grant.status.rawValue) ?? .optIn
                )
            },
            principalHandle: .init(
                kind: .init(rawValue: session.principalHandle.kind.rawValue) ?? .none,
                value: session.principalHandle.value
            ),
            linkId: session.linkId
        )
    }
}

public enum OfflineCaptureManagerError: Error, Equatable {
    case unexpectedStatus(Int)
}
