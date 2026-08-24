import Crypto
import Foundation
#if canImport(Security)
import Security
#endif

/// Failure modes for enrolling or loading a device's offline-capture signing
/// identity. Kept separate from `AuditHashError` - these are Keychain/Secure
/// Enclave failures, not canonicalization failures.
public enum AgentDeviceIdentityError: Error, Equatable {
    case keychainWrite(status: OSStatus)
    case keychainRead(status: OSStatus)
    case keychainDelete(status: OSStatus)
    case keyRepresentationInvalid
    case notEnrolled
}

/// A device's ECDSA P-256 signing identity for offline consent capture
/// (`agentDevices.publicKey` / `agentDevices.keyAlgorithm`,
/// `docs/specs/offline-consent-capture.md` §4.1-§4.2).
///
/// The private key is generated on-device and never leaves it: on hardware
/// that has one, it is generated **inside the Secure Enclave** and only an
/// encrypted, SE-wrapped blob is ever held outside it; where no Secure
/// Enclave is available (the iOS Simulator, older devices, macOS test hosts)
/// it falls back to a software key whose raw bytes live only in the
/// Keychain, still outside app-process-readable storage on-device. Both
/// paths produce the same enrollment artifact: an SPKI DER public key to
/// hand the server (`POST` to the device-enrollment console flow) and a
/// `sign(canonicalBytes:)` that never exposes key material.
public struct AgentDeviceIdentity: Sendable {
    /// `agentDevices.keyAlgorithm` - the only value this SDK produces.
    public static let keyAlgorithm = "ECDSA_P256_SHA256"

    /// base64 SPKI DER of the public key, exactly the shape `agentDevices.publicKey` expects.
    public let publicKeySPKIBase64: String

    private let signer: @Sendable (Data) throws -> P256.Signing.ECDSASignature

    init(publicKeySPKIBase64: String, signer: @escaping @Sendable (Data) throws -> P256.Signing.ECDSASignature) {
        self.publicKeySPKIBase64 = publicKeySPKIBase64
        self.signer = signer
    }

    /// Signs `canonicalBytes` (the output of `CaptureArtifact.canonicalBytes(for:)`)
    /// and returns the base64 of the raw IEEE-P1363 `r||s` pair - exactly the
    /// encoding `offlineCaptureSessions.deviceSignature` / the server's
    /// verifier expect. CryptoKit's ECDSA signing hashes the input with
    /// SHA-256 internally, matching "SHA-256 the canonical string; sign the
    /// digest" in `conformance/audit-hash-spec.md`.
    public func sign(canonicalBytes: [UInt8]) throws -> String {
        let signature = try signer(Data(canonicalBytes))
        return signature.rawRepresentation.base64EncodedString()
    }
}

/// Keychain-backed persistence + Secure-Enclave-preferring enrollment for an
/// `AgentDeviceIdentity`. One identity per `keychainTag` - typically one per
/// app install, matching one `agentDevices` row.
public enum AgentDeviceIdentityStore {
    /// A `public` default (not `private`) because a default-argument
    /// expression on a `public` function must be at least as visible as the
    /// function itself.
    public static let defaultService = "ai.dpdpguard.consent.offline.deviceIdentity"

    /// Generates a new signing key (Secure Enclave when available, software
    /// key otherwise), persists it to the Keychain under `tag`, and returns
    /// the resulting identity. Call once at device-enrollment time; the
    /// resulting `publicKeySPKIBase64` is what gets registered against
    /// `agentDevices` (console "enrol device" flow / `bulkEnrolAgentDevices`).
    ///
    /// Enrolling again under the same `tag` replaces the existing key -
    /// callers that want to keep an existing identity should call `load`
    /// first and only enroll if it returns `nil`.
    public static func enroll(tag: String = "primary", service: String = defaultService) throws -> AgentDeviceIdentity {
        try delete(tag: tag, service: service)

        #if canImport(Security) && (os(iOS) || os(macOS))
        if SecureEnclave.isAvailable {
            let key = try SecureEnclave.P256.Signing.PrivateKey()
            try persist(keyData: key.dataRepresentation, tag: tag, service: service, isSecureEnclaveWrapped: true)
            return identity(fromSecureEnclaveKey: key)
        }
        #endif

        let key = P256.Signing.PrivateKey()
        try persist(keyData: key.rawRepresentation, tag: tag, service: service, isSecureEnclaveWrapped: false)
        return identity(fromSoftwareKey: key)
    }

    /// Reloads a previously-enrolled identity, or `nil` if none has been
    /// enrolled under `tag` on this device.
    public static func load(tag: String = "primary", service: String = defaultService) throws -> AgentDeviceIdentity? {
        guard let (keyData, isSecureEnclaveWrapped) = try readKeyData(tag: tag, service: service) else {
            return nil
        }

        #if canImport(Security) && (os(iOS) || os(macOS))
        if isSecureEnclaveWrapped {
            let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: keyData)
            return identity(fromSecureEnclaveKey: key)
        }
        #endif

        let key = try P256.Signing.PrivateKey(rawRepresentation: keyData)
        return identity(fromSoftwareKey: key)
    }

    /// Removes an enrolled identity's key material from the Keychain
    /// (device decommissioning / re-enrollment). This does **not** revoke
    /// the corresponding `agentDevices` row server-side - that is a console
    /// action, since a stolen device's past captures must remain valid
    /// (`signedAt < revokedAt` semantics, §2.1).
    public static func delete(tag: String = "primary", service: String = defaultService) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AgentDeviceIdentityError.keychainDelete(status: status)
        }
        #endif
    }

    // MARK: - Private

    #if canImport(Security) && (os(iOS) || os(macOS))
    private static func identity(fromSecureEnclaveKey key: SecureEnclave.P256.Signing.PrivateKey) -> AgentDeviceIdentity {
        AgentDeviceIdentity(
            publicKeySPKIBase64: key.publicKey.derRepresentation.base64EncodedString(),
            signer: { data in try key.signature(for: data) }
        )
    }
    #endif

    private static func identity(fromSoftwareKey key: P256.Signing.PrivateKey) -> AgentDeviceIdentity {
        AgentDeviceIdentity(
            publicKeySPKIBase64: key.publicKey.derRepresentation.base64EncodedString(),
            signer: { data in try key.signature(for: data) }
        )
    }

    #if canImport(Security)
    /// Payload stored in the Keychain: a one-byte SE/software flag followed
    /// by the raw key representation, so `load` knows which key type to
    /// reconstruct without a second lookup.
    private static func persist(keyData: Data, tag: String, service: String, isSecureEnclaveWrapped: Bool) throws {
        var payload = Data([isSecureEnclaveWrapped ? 1 : 0])
        payload.append(keyData)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AgentDeviceIdentityError.keychainWrite(status: status)
        }
    }

    private static func readKeyData(tag: String, service: String) throws -> (data: Data, isSecureEnclaveWrapped: Bool)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let payload = result as? Data, payload.count > 1 else {
            throw AgentDeviceIdentityError.keychainRead(status: status)
        }
        return (data: payload.dropFirst(), isSecureEnclaveWrapped: payload[payload.startIndex] == 1)
    }
    #else
    private static func readKeyData(tag: String, service: String) throws -> (data: Data, isSecureEnclaveWrapped: Bool)? {
        nil
    }
    #endif
}
