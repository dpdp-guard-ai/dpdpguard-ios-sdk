import Foundation

/// Pure helper for gating a feature/tracker on an existing consent decision
/// — e.g. `if !hasConsent(consents, purpose: "Analytics") { return }` before
/// firing an analytics event. Does not call the network; combine with
/// ``DPDPGuardClient`` reads or your own cached consent state.
public struct ConsentRecord: Sendable, Codable, Equatable {
    public let purpose: String
    /// Present when the decision was withdrawn; `nil` means still active.
    public let withdrawnAt: Int?

    public init(purpose: String, withdrawnAt: Int? = nil) {
        self.purpose = purpose
        self.withdrawnAt = withdrawnAt
    }
}

/// `true` if `consents` contains an active (non-withdrawn) decision for
/// `purpose`.
public func hasConsent(_ consents: [ConsentRecord], purpose: String) -> Bool {
    consents.contains { $0.purpose == purpose && $0.withdrawnAt == nil }
}
