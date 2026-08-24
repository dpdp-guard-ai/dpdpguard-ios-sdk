import Crypto
import XCTest
@testable import DPDPGuardConsent

final class AgentDeviceIdentityTests: XCTestCase {
    private func uniqueService() -> String {
        "ai.dpdpguard.consent.tests.\(UUID().uuidString)"
    }

    override func tearDown() {
        // Best-effort cleanup; a leaked test key under a UUID-scoped service
        // never collides with a real enrollment or a later test run.
        super.tearDown()
    }

    func testEnrollProducesAVerifiableSignature() throws {
        let service = uniqueService()
        defer { try? AgentDeviceIdentityStore.delete(service: service) }

        let identity = try AgentDeviceIdentityStore.enroll(service: service)
        XCTAssertEqual(AgentDeviceIdentity.keyAlgorithm, "ECDSA_P256_SHA256")

        let canonicalBytes: [UInt8] = Array("dpdpcca/2 test payload".utf8)
        let signatureBase64 = try identity.sign(canonicalBytes: canonicalBytes)

        let publicKeyDER = try XCTUnwrap(Data(base64Encoded: identity.publicKeySPKIBase64))
        let publicKey = try P256.Signing.PublicKey(derRepresentation: publicKeyDER)
        let signatureData = try XCTUnwrap(Data(base64Encoded: signatureBase64))
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)

        XCTAssertTrue(publicKey.isValidSignature(signature, for: Data(canonicalBytes)))
    }

    func testLoadReturnsNilWhenNotEnrolled() throws {
        let identity = try AgentDeviceIdentityStore.load(service: uniqueService())
        XCTAssertNil(identity)
    }

    func testLoadReconstructsTheSameEnrolledIdentity() throws {
        let service = uniqueService()
        defer { try? AgentDeviceIdentityStore.delete(service: service) }

        let enrolled = try AgentDeviceIdentityStore.enroll(service: service)
        let reloaded = try XCTUnwrap(try AgentDeviceIdentityStore.load(service: service))

        XCTAssertEqual(enrolled.publicKeySPKIBase64, reloaded.publicKeySPKIBase64)
    }

    func testReEnrollingReplacesTheExistingKey() throws {
        let service = uniqueService()
        defer { try? AgentDeviceIdentityStore.delete(service: service) }

        let first = try AgentDeviceIdentityStore.enroll(service: service)
        let second = try AgentDeviceIdentityStore.enroll(service: service)

        XCTAssertNotEqual(first.publicKeySPKIBase64, second.publicKeySPKIBase64)
    }

    func testDeleteThenLoadReturnsNil() throws {
        let service = uniqueService()
        _ = try AgentDeviceIdentityStore.enroll(service: service)
        try AgentDeviceIdentityStore.delete(service: service)

        XCTAssertNil(try AgentDeviceIdentityStore.load(service: service))
    }
}
