import XCTest
@testable import DPDPGuardConsent

/// Sanity-checks that the `Codable` models decode literal JSON shaped like
/// `openapi/v1.yaml`'s schemas, and that unrecognized keys are tolerated
/// (ADR-002 D4) rather than causing a decode failure.
final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodeNotice() throws {
        let json = """
        {
          "_id": "notice_1",
          "organizationId": "org_1",
          "version": 3,
          "itemized": [
            { "purpose": "Marketing", "personalDataDescription": "Email address" }
          ],
          "content": {
            "en": { "title": "We value your privacy", "body": "Some body text." }
          },
          "status": "published"
        }
        """.data(using: .utf8)!

        let notice = try decoder.decode(Notice.self, from: json)
        XCTAssertEqual(notice.id, "notice_1")
        XCTAssertEqual(notice.organizationId, "org_1")
        XCTAssertEqual(notice.version, 3)
        XCTAssertEqual(notice.itemized.first?.purpose, "Marketing")
        XCTAssertEqual(notice.content["en"]?.title, "We value your privacy")
        XCTAssertEqual(notice.status, .published)
    }

    func testDecodeNoticeToleratesUnknownKeys() throws {
        let json = """
        {
          "_id": "notice_1",
          "organizationId": "org_1",
          "version": 1,
          "itemized": [],
          "content": {},
          "status": "draft",
          "someBrandNewFieldFromAFutureContractVersion": { "nested": true }
        }
        """.data(using: .utf8)!

        let notice = try decoder.decode(Notice.self, from: json)
        XCTAssertEqual(notice.status, .draft)
        XCTAssertTrue(notice.itemized.isEmpty)
    }

    func testDecodeDsrRequest() throws {
        let json = """
        {
          "requestId": "dsr_1",
          "type": "erasure",
          "status": "pending",
          "dueAt": 1700000000000
        }
        """.data(using: .utf8)!

        let request = try decoder.decode(DsrRequest.self, from: json)
        XCTAssertEqual(request.requestId, "dsr_1")
        XCTAssertEqual(request.type, .erasure)
        XCTAssertEqual(request.status, .pending)
        XCTAssertEqual(request.dueAt, 1_700_000_000_000)
        XCTAssertNil(request.requestDetails)
    }

    func testDecodeGrievanceWithInProgressStatus() throws {
        let json = """
        {
          "grievanceId": "griev_1",
          "subject": "Data retained too long",
          "description": "Please delete my data.",
          "status": "in_progress",
          "dueAt": 1700000000000
        }
        """.data(using: .utf8)!

        let grievance = try decoder.decode(Grievance.self, from: json)
        XCTAssertEqual(grievance.status, .inProgress)
        XCTAssertNil(grievance.response)
    }

    func testDecodeNomination() throws {
        let json = """
        {
          "nominationId": "nom_1",
          "nomineeName": "Jane Doe",
          "nomineeContact": "jane@example.com",
          "status": "active"
        }
        """.data(using: .utf8)!

        let nomination = try decoder.decode(Nomination.self, from: json)
        XCTAssertEqual(nomination.status, .active)
        XCTAssertEqual(nomination.nomineeName, "Jane Doe")
    }

    func testDecodeApiErrorBody() throws {
        let json = """
        { "code": "RATE_LIMITED", "error": "Too many requests." }
        """.data(using: .utf8)!

        let body = try decoder.decode(ApiErrorBody.self, from: json)
        XCTAssertEqual(body.code, "RATE_LIMITED")
        XCTAssertEqual(body.error, "Too many requests.")
    }

    func testDecodeBannerConfigWithArbitraryBannerSettings() throws {
        let json = """
        {
          "bannerSettings": { "primaryColor": "#123456", "showLogo": true, "position": "bottom" },
          "configVersion": 4
        }
        """.data(using: .utf8)!

        let config = try decoder.decode(BannerConfigResponse.self, from: json)
        XCTAssertEqual(config.configVersion, 4)

        guard case .string(let primaryColor)? = config.bannerSettings?["primaryColor"] else {
            XCTFail("Expected primaryColor to decode as a string JSONValue")
            return
        }
        XCTAssertEqual(primaryColor, "#123456")

        guard case .bool(let showLogo)? = config.bannerSettings?["showLogo"] else {
            XCTFail("Expected showLogo to decode as a bool JSONValue")
            return
        }
        XCTAssertTrue(showLogo)
    }

    func testEncodeCreateDsrRequestInputOmitsNilDetails() throws {
        let input = CreateDsrRequestInput(organizationId: "org_1", type: .summary)
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
        XCTAssertNil(decoded["details"])
        guard case .string(let orgId)? = decoded["organizationId"] else {
            XCTFail("Expected organizationId to encode as a string")
            return
        }
        XCTAssertEqual(orgId, "org_1")
    }
}
