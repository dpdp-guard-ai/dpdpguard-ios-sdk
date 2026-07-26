import XCTest
@testable import DPDPGuardConsent

/// ADR-002 D5 hard release gate: this SDK's audit-hash implementation must
/// reproduce `conformance/audit-hash-vectors.json`'s golden vectors
/// byte-for-byte. The JSON file bundled at
/// `Tests/DPDPGuardConsentTests/Resources/audit-hash-vectors.json` is a
/// verbatim copy of the `dpdpbot` repo's file — do not hand-edit it.
final class AuditHashTests: XCTestCase {
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
        let givenAt: Int
        let source: ConsentSource?
    }

    private struct MissingResourceError: Error, CustomStringConvertible {
        var description: String {
            "audit-hash-vectors.json not found among the test target's bundled resources."
        }
    }

    private func loadVectorFile() throws -> VectorFile {
        let url = Bundle.module.url(
            forResource: "audit-hash-vectors",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(
            forResource: "audit-hash-vectors",
            withExtension: "json"
        )

        guard let resourceURL = url else {
            XCTFail("audit-hash-vectors.json not found among the test target's bundled resources.")
            throw MissingResourceError()
        }

        let data = try Data(contentsOf: resourceURL)
        return try JSONDecoder().decode(VectorFile.self, from: data)
    }

    func testGoldenVectorsMatchCanonicalizationAndHash() throws {
        let file = try loadVectorFile()

        XCTAssertFalse(file.vectors.isEmpty, "Expected at least one golden vector in audit-hash-vectors.json")

        for vector in file.vectors {
            let input = AuditHashInput(
                organizationId: vector.input.organizationId,
                noticeId: vector.input.noticeId,
                noticeVersion: vector.input.noticeVersion,
                purpose: vector.input.purpose,
                dataTypes: vector.input.dataTypes,
                givenAt: vector.input.givenAt,
                source: vector.input.source
            )

            let canonical = AuditHash.canonicalize(input)
            XCTAssertEqual(
                canonical,
                vector.expectedCanonical,
                "canonicalization mismatch for vector \"\(vector.name)\""
            )

            let hash = AuditHash.compute(input, secret: file.testSecret)
            XCTAssertEqual(
                hash,
                vector.expectedHash,
                "hash mismatch for vector \"\(vector.name)\""
            )
        }
    }

    func testNilSourceCanonicalizesToLiteralNullString() {
        let input = AuditHashInput(
            organizationId: "org_x",
            noticeId: "notice_x",
            noticeVersion: 1,
            purpose: "Test",
            dataTypes: ["a"],
            givenAt: 1,
            source: nil
        )
        XCTAssertTrue(AuditHash.canonicalize(input).hasSuffix("|null"))
    }

    func testDataTypesAreSortedRegardlessOfInputOrder() {
        let unsorted = AuditHashInput(
            organizationId: "org_x",
            noticeId: "notice_x",
            noticeVersion: 1,
            purpose: "Test",
            dataTypes: ["phone", "email"],
            givenAt: 1,
            source: .direct
        )
        let sorted = AuditHashInput(
            organizationId: "org_x",
            noticeId: "notice_x",
            noticeVersion: 1,
            purpose: "Test",
            dataTypes: ["email", "phone"],
            givenAt: 1,
            source: .direct
        )
        XCTAssertEqual(AuditHash.canonicalize(unsorted), AuditHash.canonicalize(sorted))
    }
}
