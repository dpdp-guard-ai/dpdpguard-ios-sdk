import XCTest
@testable import DPDPGuardConsent

final class ConsentGateTests: XCTestCase {
    func testHasConsentTrueForActiveConsent() {
        let consents = [ConsentRecord(purpose: "Analytics", withdrawnAt: nil)]
        XCTAssertTrue(hasConsent(consents, purpose: "Analytics"))
    }

    func testHasConsentFalseWhenWithdrawn() {
        let consents = [ConsentRecord(purpose: "Analytics", withdrawnAt: 1_700_000_000_000)]
        XCTAssertFalse(hasConsent(consents, purpose: "Analytics"))
    }

    func testHasConsentFalseWhenPurposeAbsent() {
        let consents = [ConsentRecord(purpose: "Newsletter", withdrawnAt: nil)]
        XCTAssertFalse(hasConsent(consents, purpose: "Analytics"))
    }

    func testHasConsentTrueWhenAnyMatchingRecordIsActive() {
        let consents = [
            ConsentRecord(purpose: "Analytics", withdrawnAt: 1_700_000_000_000),
            ConsentRecord(purpose: "Analytics", withdrawnAt: nil)
        ]
        XCTAssertTrue(hasConsent(consents, purpose: "Analytics"))
    }

    func testHasConsentFalseForEmptyList() {
        XCTAssertFalse(hasConsent([], purpose: "Analytics"))
    }
}
