import XCTest
@testable import DPDPGuardConsent

final class ErrorCatalogTests: XCTestCase {
    func testCatalogHasTenCodes() {
        XCTAssertEqual(errorCatalog.count, 10)
    }

    func testEveryApiErrorCodeCaseHasACatalogEntry() {
        let catalogCodes = Set(errorCatalog.map(\.code))
        for errorCode in ApiErrorCode.allCases {
            XCTAssertTrue(
                catalogCodes.contains(errorCode.rawValue),
                "Missing catalog entry for \(errorCode.rawValue)"
            )
        }
    }

    func testCatalogHasNoDuplicateCodes() {
        let codes = errorCatalog.map(\.code)
        XCTAssertEqual(codes.count, Set(codes).count)
    }

    func testApiErrorExposesKnownCode() {
        let error = DPDPGuardApiError(code: "NOT_FOUND", message: "missing", status: 404)
        XCTAssertEqual(error.knownCode, .notFound)
    }

    func testApiErrorWithUnrecognizedCodeHasNilKnownCode() {
        let error = DPDPGuardApiError(code: "SOME_FUTURE_CODE", message: "?", status: 400)
        XCTAssertNil(error.knownCode)
        XCTAssertEqual(error.code, "SOME_FUTURE_CODE")
    }
}
