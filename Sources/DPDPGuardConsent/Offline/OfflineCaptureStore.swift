import Crypto
import Foundation
#if canImport(Security)
import Security
#endif

public enum OfflineCaptureStoreError: Error, Equatable {
    case keychainWrite(status: OSStatus)
    case keychainRead(status: OSStatus)
    case directoryUnavailable
    case corruptRecord(clientSessionId: UUID)
}

/// The encrypted local store for pending offline captures
/// (`docs/specs/offline-consent-capture.md` §4.1): "an encrypted local
/// store … holds: the pre-cached notice bundles … the pending
/// `offlineCaptureSessions`, and nothing else. Cached PII is bounded - a
/// capture is evicted from local storage once its sync is
/// server-acknowledged."
///
/// This SDK stores only the pending-session half of that (notice-bundle
/// caching is a host-app concern - notices are public, non-PII content
/// fetched via `GET /api/v1/notices/{noticeId}`). Each session is
/// AES-256-GCM sealed with a per-install symmetric key held in the Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synced to
/// iCloud Keychain, never exported) and written as one file per
/// `clientSessionId` under an `isExcludedFromBackup` directory, so a
/// captured-but-unsynced principal handle never lands in an iCloud/iTunes
/// device backup.
public final class OfflineCaptureStore: @unchecked Sendable {
    private let directory: URL
    private let key: SymmetricKey
    private let lock = NSLock()

    /// - Parameters:
    ///   - directory: Where sealed session files are written. Defaults to
    ///     `Application Support/ai.dpdpguard.consent/offline-captures`,
    ///     created on first use and marked excluded from device backups.
    ///   - keychainService: Keychain service string scoping the AES key, in
    ///     case a host app runs multiple independently-enrolled devices in
    ///     one process (rare, but e.g. a POS fleet simulator).
    public init(
        directory: URL? = nil,
        keychainService: String = "ai.dpdpguard.consent.offline.storeKey"
    ) throws {
        self.directory = try directory ?? Self.defaultDirectory()
        self.key = try Self.loadOrCreateKey(service: keychainService)
        try Self.prepareDirectory(self.directory)
    }

    /// Persists `session`, sealed with the store's key. Overwrites any
    /// existing record for the same `clientSessionId` (re-signing the same
    /// session is not a supported flow - `OfflineCaptureManager.capture`
    /// always mints a fresh `clientSessionId` - but this keeps `save` safe
    /// to call twice for the same value).
    public func save(_ session: OfflineCaptureSession) throws {
        let data = try JSONEncoder().encode(session)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw OfflineCaptureStoreError.corruptRecord(clientSessionId: session.clientSessionId)
        }
        lock.lock()
        defer { lock.unlock() }
        try combined.write(to: fileURL(for: session.clientSessionId), options: .atomic)
    }

    /// All sessions currently pending sync, in no particular order. A record
    /// that fails to decrypt or decode is skipped rather than thrown for -
    /// one corrupt file must not block every other queued capture - but its
    /// id is included in the thrown `corruptFiles` diagnostic on
    /// `loadPendingReportingCorruption()` for callers that want to know.
    public func loadPending() throws -> [OfflineCaptureSession] {
        try loadPendingReportingCorruption().sessions
    }

    /// Same as `loadPending()`, but also reports which files could not be
    /// read back (e.g. truncated by a crash mid-write, or sealed under a key
    /// that no longer matches after a Keychain reset).
    public func loadPendingReportingCorruption() throws -> (sessions: [OfflineCaptureSession], corruptFiles: [URL]) {
        lock.lock()
        defer { lock.unlock() }

        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == Self.fileExtension }

        var sessions: [OfflineCaptureSession] = []
        var corruptFiles: [URL] = []
        for file in files {
            guard
                let combined = try? Data(contentsOf: file),
                let box = try? AES.GCM.SealedBox(combined: combined),
                let opened = try? AES.GCM.open(box, using: key),
                let session = try? JSONDecoder().decode(OfflineCaptureSession.self, from: opened)
            else {
                corruptFiles.append(file)
                continue
            }
            sessions.append(session)
        }
        return (sessions, corruptFiles)
    }

    /// Evicts a session from local storage - call once its sync result has
    /// been acknowledged by the server (`OfflineCaptureResult`, any status:
    /// `verified`, `quarantined`, and `rejected` are all terminal
    /// server-side acknowledgements, not just success). A session with no
    /// on-disk record is treated as already-evicted, not an error.
    public func remove(clientSessionId: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(for: clientSessionId)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Removes every pending session and its backing file. Intended for
    /// device decommissioning (paired with `AgentDeviceIdentityStore.delete`)
    /// or test teardown - not part of the normal sync flow.
    public func removeAll() throws {
        lock.lock()
        defer { lock.unlock() }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            try FileManager.default.removeItem(at: file)
        }
    }

    /// Removes the store's AES key from the Keychain (device
    /// decommissioning / test teardown). Any files still on disk under this
    /// store's `directory` become permanently undecryptable once this runs -
    /// callers that want the pending sessions themselves gone should call
    /// `removeAll()` first.
    public static func deleteKey(keychainService: String = "ai.dpdpguard.consent.offline.storeKey") throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "aes256gcm"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OfflineCaptureStoreError.keychainWrite(status: status)
        }
        #endif
    }

    // MARK: - Private

    private static let fileExtension = "dpdpcapture"

    private func fileURL(for clientSessionId: UUID) -> URL {
        directory.appendingPathComponent(clientSessionId.uuidString.lowercased()).appendingPathExtension(Self.fileExtension)
    }

    private static func defaultDirectory() throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OfflineCaptureStoreError.directoryUnavailable
        }
        return base
            .appendingPathComponent("ai.dpdpguard.consent", isDirectory: true)
            .appendingPathComponent("offline-captures", isDirectory: true)
    }

    private static func prepareDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var mutableDirectory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableDirectory.setResourceValues(values)
    }

    #if canImport(Security)
    private static func loadOrCreateKey(service: String) throws -> SymmetricKey {
        let account = "aes256gcm"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound else {
            throw OfflineCaptureStoreError.keychainRead(status: status)
        }

        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OfflineCaptureStoreError.keychainWrite(status: addStatus)
        }
        return newKey
    }
    #else
    private static func loadOrCreateKey(service: String) throws -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
    #endif
}
