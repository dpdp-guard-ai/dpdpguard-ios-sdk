import Foundation

/// Auth mode for an individual request.
enum DPDPGuardAuthMode: Sendable {
    case none
    case apiKey
    case bearer
}

/// Non-API-error failures raised by ``DPDPGuardClient`` itself — a locally
/// detected problem (bad URL, missing credential, non-HTTP response) as
/// opposed to a typed, catalog-backed error returned by the server (see
/// ``DPDPGuardApiError``).
public enum DPDPGuardClientError: Error, Sendable, CustomStringConvertible {
    case invalidURL
    case invalidResponse
    case missingCredential(String)

    public var description: String {
        switch self {
        case .invalidURL:
            return "DPDPGuardClient: constructed an invalid URL for this request."
        case .invalidResponse:
            return "DPDPGuardClient: received a non-HTTP response."
        case .missingCredential(let message):
            return "DPDPGuardClient: \(message)"
        }
    }
}

/// Configuration used to construct a ``DPDPGuardClient``.
public struct DPDPGuardClientOptions: Sendable {
    /// e.g. `https://trustworthy-alligator-303.convex.site`
    public var baseURL: URL
    /// Service API key (`convex/apiKeys.ts`) — required for `brokerToken()`.
    public var apiKey: String?
    /// A brokered principal access token, if you already minted one.
    public var accessToken: String?
    /// Override for testing; defaults to `URLSession.shared`.
    public var urlSession: URLSession

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        accessToken: String? = nil,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.accessToken = accessToken
        self.urlSession = urlSession
    }
}

/// Thin typed client over DPDP Guard's public `/api/v1` surface (spec
/// §4.2), mirroring the Node reference SDK's `DpdpGuardClient`
/// (`dpdpguard-server-node-sdk/src/client.ts`). Maps every non-2xx response
/// to a ``DPDPGuardApiError`` keyed by the ADR-002 error catalog's `code`.
///
/// This is an `actor` because it owns one mutable field (`accessToken`, set
/// by `brokerToken()` or `setAccessToken(_:)`) that may be read and written
/// from concurrent `Task`s — isolating it in an actor is safer than a class
/// with manual locking.
///
/// Networking is done via the completion-handler `URLSessionDataTask` API
/// wrapped in `withCheckedThrowingContinuation`, rather than
/// `URLSession.data(for:)` (which requires iOS 15+) — this keeps the
/// package's iOS 14 deployment floor (`Package.swift`) intact.
public actor DPDPGuardClient {
    private static let pathComponentAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()

    private let baseURL: URL
    private let apiKey: String?
    private var accessToken: String?
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(options: DPDPGuardClientOptions) {
        self.baseURL = options.baseURL
        self.apiKey = options.apiKey
        self.accessToken = options.accessToken
        self.urlSession = options.urlSession
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    /// Set/replace the brokered principal access token (e.g. after
    /// re-brokering on expiry).
    public func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    // MARK: - Public reads (no auth)

    public func getOrganization(slug: String) async throws -> OrgSummary {
        try await decodedRequest(
            method: "GET",
            path: "/api/v1/org/\(Self.encodedPathComponent(slug))",
            auth: .none
        )
    }

    public func getNotices(orgId: String) async throws -> NoticesResponse {
        try await decodedRequest(
            method: "GET",
            path: "/api/v1/org/\(Self.encodedPathComponent(orgId))/notices",
            auth: .none
        )
    }

    public func getNotice(noticeId: String) async throws -> Notice {
        try await decodedRequest(
            method: "GET",
            path: "/api/v1/notices/\(Self.encodedPathComponent(noticeId))",
            auth: .none
        )
    }

    /// ADR-006 D2: pass `domain` for the web scope, `appId` for the
    /// native-app scope, or neither for org-default.
    public func getBannerConfig(
        orgId: String,
        domain: String? = nil,
        appId: String? = nil
    ) async throws -> BannerConfigResponse {
        var queryItems: [URLQueryItem] = []
        if let domain {
            queryItems.append(URLQueryItem(name: "domain", value: domain))
        }
        if let appId {
            queryItems.append(URLQueryItem(name: "appId", value: appId))
        }
        return try await decodedRequest(
            method: "GET",
            path: "/api/v1/org/\(Self.encodedPathComponent(orgId))/banner-config",
            queryItems: queryItems,
            auth: .none
        )
    }

    // MARK: - Auth (ADR-004)

    /// Mints a brokered principal access token using the service API key,
    /// and stores it on this client for subsequent authenticated calls.
    @discardableResult
    public func brokerToken(externalId: String) async throws -> BrokerTokenResponse {
        let result: BrokerTokenResponse = try await decodedRequest(
            method: "POST",
            path: "/api/v1/auth/broker-token",
            body: BrokerTokenRequestBody(externalId: externalId),
            auth: .apiKey
        )
        self.accessToken = result.accessToken
        return result
    }

    /// Reconciles a guest's anonymous consent trail into the now-known
    /// principal (ADR-004 D3). Requires a brokered access token.
    public func linkAnonymousConsent(anonymousId: String) async throws -> LinkAnonymousConsentResponse {
        try await decodedRequest(
            method: "POST",
            path: "/api/v1/link-anonymous-consent",
            body: LinkAnonymousConsentRequestBody(anonymousId: anonymousId),
            auth: .bearer
        )
    }

    // MARK: - DSR (spec §4.2)

    public func listDsrRequests() async throws -> ListDsrRequestsResponse {
        try await decodedRequest(method: "GET", path: "/api/v1/dsr", auth: .bearer)
    }

    public func createDsrRequest(
        _ input: CreateDsrRequestInput,
        idempotencyKey: String? = nil
    ) async throws -> DsrRequest {
        try await decodedRequest(
            method: "POST",
            path: "/api/v1/dsr",
            body: input,
            auth: .bearer,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: - Grievances (spec §4.2)

    public func listGrievances() async throws -> ListGrievancesResponse {
        try await decodedRequest(method: "GET", path: "/api/v1/grievances", auth: .bearer)
    }

    public func createGrievance(
        _ input: CreateGrievanceInput,
        idempotencyKey: String? = nil
    ) async throws -> Grievance {
        try await decodedRequest(
            method: "POST",
            path: "/api/v1/grievances",
            body: input,
            auth: .bearer,
            idempotencyKey: idempotencyKey
        )
    }

    // MARK: - Nomination (spec §4.2)

    public func getNomination() async throws -> Nomination? {
        let data = try await performRequest(
            method: "GET",
            path: "/api/v1/nomination",
            auth: .bearer
        )
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" {
            return nil
        }
        return try decoder.decode(Nomination.self, from: data)
    }

    public func upsertNomination(nomineeName: String, nomineeContact: String) async throws -> Nomination {
        try await decodedRequest(
            method: "PUT",
            path: "/api/v1/nomination",
            body: UpsertNominationInput(nomineeName: nomineeName, nomineeContact: nomineeContact),
            auth: .bearer
        )
    }

    public func revokeNomination() async throws -> RevokeNominationResponse {
        try await decodedRequest(method: "DELETE", path: "/api/v1/nomination", auth: .bearer)
    }

    // MARK: - Request plumbing

    private func decodedRequest<Response: Decodable & Sendable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        auth: DPDPGuardAuthMode = .bearer,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        let data = try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: nil,
            auth: auth,
            idempotencyKey: idempotencyKey
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func decodedRequest<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Body,
        auth: DPDPGuardAuthMode = .bearer,
        idempotencyKey: String? = nil
    ) async throws -> Response {
        let bodyData = try encoder.encode(body)
        let data = try await performRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            bodyData: bodyData,
            auth: auth,
            idempotencyKey: idempotencyKey
        )
        return try decoder.decode(Response.self, from: data)
    }

    private func performRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        bodyData: Data? = nil,
        auth: DPDPGuardAuthMode,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        var baseString = baseURL.absoluteString
        if baseString.hasSuffix("/") {
            baseString.removeLast()
        }
        guard var components = URLComponents(string: baseString + path) else {
            throw DPDPGuardClientError.invalidURL
        }
        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw DPDPGuardClientError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        switch auth {
        case .none:
            break
        case .apiKey:
            guard let apiKey else {
                throw DPDPGuardClientError.missingCredential(
                    "this call requires `apiKey` to be set when constructing DPDPGuardClient."
                )
            }
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .bearer:
            guard let accessToken else {
                throw DPDPGuardClientError.missingCredential(
                    "this call requires an access token — call brokerToken() first, or pass `accessToken` when constructing DPDPGuardClient."
                )
            }
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if let idempotencyKey {
            urlRequest.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }

        if let bodyData {
            urlRequest.httpBody = bodyData
        }

        let (data, response) = try await Self.send(urlRequest, using: urlSession)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DPDPGuardClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let apiError = try? decoder.decode(ApiErrorBody.self, from: data) {
                throw DPDPGuardApiError(code: apiError.code, message: apiError.error, status: httpResponse.statusCode)
            }
            throw DPDPGuardApiError(
                code: ApiErrorCode.validationError.rawValue,
                message: "Request failed with status \(httpResponse.statusCode).",
                status: httpResponse.statusCode
            )
        }

        return data
    }

    /// Bridges the completion-handler `URLSessionDataTask` API to
    /// async/await. Deliberately not `URLSession.data(for:)` (iOS 15+) so
    /// this stays usable down to the package's iOS 14 floor.
    private static func send(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: DPDPGuardClientError.invalidResponse)
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    private static func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: pathComponentAllowedCharacters) ?? value
    }
}
