import XCTest
@testable import DPDPGuardConsent

/// Fails if Sources/DPDPGuardConsent/Generated/ApiErrorCode.swift has drifted
/// from contract/conformance/error-catalog.json (ADR-002 D2) - re-run
/// scripts/generate-error-codes.mjs and commit the diff if this fails.
final class ApiErrorCodeConformanceTests: XCTestCase {
    private struct CatalogFile: Decodable {
        struct Entry: Decodable { let code: String }
        let codes: [Entry]
    }

    func testGeneratedEnumMatchesCatalog() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "error-catalog", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(CatalogFile.self, from: data)

        let catalogCodes = Set(catalog.codes.map(\.code))
        let enumCodes = Set(ApiErrorCode.allCases.map(\.rawValue))

        XCTAssertEqual(enumCodes, catalogCodes)
    }
}
