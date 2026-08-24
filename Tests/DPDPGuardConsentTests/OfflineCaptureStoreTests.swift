import XCTest
@testable import DPDPGuardConsent

final class OfflineCaptureStoreTests: XCTestCase {
    private func makeStore() throws -> (store: OfflineCaptureStore, directory: URL, service: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let service = "ai.dpdpguard.consent.tests.store.\(UUID().uuidString)"
        let store = try OfflineCaptureStore(directory: directory, keychainService: service)
        return (store, directory, service)
    }

    private func sampleSession(id: UUID = UUID()) -> OfflineCaptureSession {
        OfflineCaptureSession(
            clientSessionId: id,
            organizationId: "org_abc123",
            deviceId: "device_pune_114",
            noticeId: "notice_v3",
            noticeVersion: 3,
            noticeLocale: "hi",
            channel: .agentApp,
            capturedAtClient: 1_700_000_000_000,
            deviceSignatureBase64: "deadbeef==",
            dataTypes: ["pan"],
            purposeGrants: [PurposeGrant(purposeKey: "kyc_verification", purposeLabel: "KYC", category: .essential, status: .optIn)],
            principalHandle: PrincipalHandle(kind: .phoneHash, value: "9876543210")
        )
    }

    override func tearDown() {
        super.tearDown()
    }

    func testSaveThenLoadPendingRoundTrips() throws {
        let (store, directory, service) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? OfflineCaptureStore.deleteKey(keychainService: service)
        }

        let session = sampleSession()
        try store.save(session)

        let pending = try store.loadPending()
        XCTAssertEqual(pending, [session])
    }

    func testRemoveEvictsASession() throws {
        let (store, directory, service) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? OfflineCaptureStore.deleteKey(keychainService: service)
        }

        let session = sampleSession()
        try store.save(session)
        try store.remove(clientSessionId: session.clientSessionId)

        XCTAssertEqual(try store.loadPending(), [])
    }

    func testRemovingAnUnknownSessionIsNotAnError() throws {
        let (store, directory, service) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? OfflineCaptureStore.deleteKey(keychainService: service)
        }

        XCTAssertNoThrow(try store.remove(clientSessionId: UUID()))
    }

    func testMultipleSessionsAllPersist() throws {
        let (store, directory, service) = try makeStore()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? OfflineCaptureStore.deleteKey(keychainService: service)
        }

        let sessions = (0..<5).map { _ in sampleSession() }
        for session in sessions {
            try store.save(session)
        }

        let pending = Set(try store.loadPending().map(\.clientSessionId))
        XCTAssertEqual(pending, Set(sessions.map(\.clientSessionId)))
    }

    func testADifferentStoreInstanceCannotDecryptAnotherStoresFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let serviceA = "ai.dpdpguard.consent.tests.store.\(UUID().uuidString)"
        let serviceB = "ai.dpdpguard.consent.tests.store.\(UUID().uuidString)"
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? OfflineCaptureStore.deleteKey(keychainService: serviceA)
            try? OfflineCaptureStore.deleteKey(keychainService: serviceB)
        }

        let storeA = try OfflineCaptureStore(directory: directory, keychainService: serviceA)
        try storeA.save(sampleSession())

        let storeB = try OfflineCaptureStore(directory: directory, keychainService: serviceB)
        let (sessions, corruptFiles) = try storeB.loadPendingReportingCorruption()

        XCTAssertEqual(sessions, [])
        XCTAssertEqual(corruptFiles.count, 1)
    }
}
