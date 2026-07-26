import XCTest
@testable import DPDPGuardConsent

/// Replays contract/conformance/audit-hash-vectors.json (ADR-002 D5) - the
/// required cross-SDK gate proving this implementation is byte-for-byte
/// identical to convex/lib/auditHash.ts.
final class AuditHashConformanceTests: XCTestCase {
    private struct VectorFile: Decodable {
        let testSecret: String
        let vectors: [Vector]
    }

    private struct Vector: Decodable {
        let name: String
        let input: VectorInput
        let expectedCanonical: String
        let expectedHash: String
    }

    private struct VectorInput: Decodable {
        let organizationId: String
        let noticeId: String
        let noticeVersion: Int
        let purpose: String
        let dataTypes: [String]
        let givenAt: Int64
        let source: String?
    }

    func testGoldenVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "audit-hash-vectors", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(VectorFile.self, from: data)

        for vector in file.vectors {
            let input = AuditHashInput(
                organizationId: vector.input.organizationId,
                noticeId: vector.input.noticeId,
                noticeVersion: vector.input.noticeVersion,
                purpose: vector.input.purpose,
                dataTypes: vector.input.dataTypes,
                givenAt: vector.input.givenAt,
                source: vector.input.source.flatMap(AuditHashSource.init(rawValue:))
            )

            XCTAssertEqual(
                canonicalAuditString(input),
                vector.expectedCanonical,
                "canonical string mismatch for vector \"\(vector.name)\""
            )

            let hash = try computeAuditHash(input, secret: file.testSecret)
            XCTAssertEqual(hash, vector.expectedHash, "hash mismatch for vector \"\(vector.name)\"")
        }
    }

    func testMissingSecretThrows() {
        let input = AuditHashInput(
            organizationId: "org",
            noticeId: "notice",
            noticeVersion: 1,
            purpose: "Newsletter",
            dataTypes: ["email"],
            givenAt: 0,
            source: .direct
        )
        XCTAssertThrowsError(try computeAuditHash(input, secret: "")) {
            XCTAssertEqual($0 as? AuditHashError, .missingSecret)
        }
    }
}
