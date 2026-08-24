import Crypto
import XCTest
@testable import DPDPGuardConsent

final class OfflineCaptureManagerTests: XCTestCase {
    private func makeManager() throws -> (manager: OfflineCaptureManager, identityService: String, storeDirectory: URL, storeService: String) {
        let identityService = "ai.dpdpguard.consent.tests.identity.\(UUID().uuidString)"
        let storeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeService = "ai.dpdpguard.consent.tests.store.\(UUID().uuidString)"

        let identity = try AgentDeviceIdentityStore.enroll(service: identityService)
        let store = try OfflineCaptureStore(directory: storeDirectory, keychainService: storeService)
        return (OfflineCaptureManager(identity: identity, store: store), identityService, storeDirectory, storeService)
    }

    func testCapturePersistsASignedSessionThatVerifiesAgainstTheEnrolledPublicKey() throws {
        let (manager, identityService, storeDirectory, storeService) = try makeManager()
        defer {
            try? AgentDeviceIdentityStore.delete(service: identityService)
            try? FileManager.default.removeItem(at: storeDirectory)
            try? OfflineCaptureStore.deleteKey(keychainService: storeService)
        }
        let identity = try XCTUnwrap(try AgentDeviceIdentityStore.load(service: identityService))

        let session = try manager.capture(
            deviceId: "device_pune_114",
            organizationId: "org_abc123",
            noticeId: "notice_v3",
            noticeVersion: 3,
            noticeLocale: "hi",
            purposeGrants: [PurposeGrant(purposeKey: "kyc_verification", purposeLabel: "KYC", category: .essential, status: .optIn)],
            dataTypes: ["pan"],
            principalHandle: PrincipalHandle(kind: .phoneHash, value: "9876543210"),
            channel: .agentApp,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertEqual(try manager.pendingSessions(), [session])

        let artifactInput = CaptureArtifactInput(
            clientSessionId: session.clientSessionId,
            organizationId: session.organizationId,
            deviceId: session.deviceId,
            noticeId: session.noticeId,
            noticeVersion: session.noticeVersion,
            noticeLocale: session.noticeLocale,
            purposeGrants: session.purposeGrants,
            dataTypes: session.dataTypes,
            principalHandle: session.principalHandle,
            capturedAtClient: session.capturedAtClient,
            channel: session.channel
        )
        let canonicalBytes = CaptureArtifact.canonicalBytes(for: artifactInput)

        let publicKeyDER = try XCTUnwrap(Data(base64Encoded: identity.publicKeySPKIBase64))
        let publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyDER)
        let signatureData = try XCTUnwrap(Data(base64Encoded: session.deviceSignatureBase64))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(canonicalBytes)))
    }

    func testEachCaptureGetsAFreshClientSessionId() throws {
        let (manager, identityService, storeDirectory, storeService) = try makeManager()
        defer {
            try? AgentDeviceIdentityStore.delete(service: identityService)
            try? FileManager.default.removeItem(at: storeDirectory)
            try? OfflineCaptureStore.deleteKey(keychainService: storeService)
        }

        func captureOnce() throws -> OfflineCaptureSession {
            try manager.capture(
                deviceId: "device_pune_114",
                organizationId: "org_abc123",
                noticeId: "notice_v3",
                noticeVersion: 3,
                noticeLocale: "hi",
                purposeGrants: [PurposeGrant(purposeKey: "kyc_verification", purposeLabel: "KYC", category: .essential, status: .optIn)],
                dataTypes: ["pan"],
                principalHandle: .none,
                channel: .agentApp
            )
        }

        let first = try captureOnce()
        let second = try captureOnce()

        XCTAssertNotEqual(first.clientSessionId, second.clientSessionId)
        XCTAssertEqual(Set(try manager.pendingSessions().map(\.clientSessionId)), [first.clientSessionId, second.clientSessionId])
    }
}
