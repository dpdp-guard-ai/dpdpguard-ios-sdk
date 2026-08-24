import XCTest
@testable import DPDPGuardConsent

/// Replays contract/conformance/capture-artifact-vectors.json - the
/// cross-SDK gate proving this implementation's `dpdpcca/2` canonicalization
/// is byte-for-byte identical to `convex/lib/captureArtifact.ts`. Device
/// signatures are ECDSA and non-deterministic (per the vector file's own
/// description), so only `expectedCanonical` is pinned here; the signing
/// round-trip itself is covered by `AgentDeviceIdentityTests`.
final class CaptureArtifactConformanceTests: XCTestCase {
    private struct VectorFile: Decodable {
        let vectors: [Vector]
    }

    private struct Vector: Decodable {
        let name: String
        let input: VectorInput
        let expectedCanonical: String
    }

    private struct VectorInput: Decodable {
        let clientSessionId: UUID
        let organizationId: String
        let deviceId: String
        let noticeId: String
        let noticeVersion: Int
        let noticeLocale: String
        let purposeGrants: [VectorPurposeGrant]
        let dataTypes: [String]
        let principalHandleKind: String
        let principalHandleValue: String
        let capturedAtClient: Int64
        let channel: String
    }

    private struct VectorPurposeGrant: Decodable {
        let purposeKey: String
        let status: String
    }

    func testGoldenVectors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "capture-artifact-vectors", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(VectorFile.self, from: data)

        for vector in file.vectors {
            let input = CaptureArtifactInput(
                clientSessionId: vector.input.clientSessionId,
                organizationId: vector.input.organizationId,
                deviceId: vector.input.deviceId,
                noticeId: vector.input.noticeId,
                noticeVersion: vector.input.noticeVersion,
                noticeLocale: vector.input.noticeLocale,
                // purposeLabel/category aren't part of the canonical string
                // (see conformance/audit-hash-spec.md's field table) so any
                // value is fine here - only purposeKey/status are signed.
                purposeGrants: vector.input.purposeGrants.map {
                    PurposeGrant(
                        purposeKey: $0.purposeKey,
                        purposeLabel: $0.purposeKey,
                        category: .essential,
                        status: PurposeGrantStatus(rawValue: $0.status)!
                    )
                },
                dataTypes: vector.input.dataTypes,
                principalHandle: PrincipalHandle(
                    kind: PrincipalHandleKind(rawValue: vector.input.principalHandleKind)!,
                    value: vector.input.principalHandleValue
                ),
                capturedAtClient: vector.input.capturedAtClient,
                channel: CaptureChannel(rawValue: vector.input.channel)!
            )

            XCTAssertEqual(
                CaptureArtifact.canonicalString(for: input),
                vector.expectedCanonical,
                "canonical string mismatch for vector \"\(vector.name)\""
            )
        }
    }

    func testEmptyPrincipalHandleSerializesAsLiteralNull() {
        let input = CaptureArtifactInput(
            clientSessionId: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            organizationId: "org_abc123",
            deviceId: "device_pos_7",
            noticeId: "notice_v1",
            noticeVersion: 1,
            noticeLocale: "en",
            purposeGrants: [PurposeGrant(purposeKey: "loyalty", purposeLabel: "loyalty", category: .essential, status: .optIn)],
            dataTypes: ["phone"],
            principalHandle: .none,
            capturedAtClient: 1_700_000_050_000,
            channel: .pos
        )

        XCTAssertTrue(CaptureArtifact.canonicalString(for: input).hasSuffix("|4:none|4:null|13:1700000050000|3:pos"))
    }
}
