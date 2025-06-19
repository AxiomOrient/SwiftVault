import Foundation
import Combine
import OSLog

#if canImport(UIKit)
import UIKit

@MainActor
private final class ForegroundObserver: Sendable {
    private nonisolated let tokenContainer: ObserverTokenContainer
    private let logger = Logger(subsystem: SwiftVault.Config.defaultLoggerSubsystem, category: "ForegroundObserver")
    
    init(handler: @escaping @Sendable () -> Void) {
        let token = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            handler()
        }
        self.tokenContainer = ObserverTokenContainer(token: token)
        logger.debug("Subscribed to willEnterForegroundNotification.")
    }
    
    deinit {
        if let token = tokenContainer.take() {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
#endif

/// `Keychain`을 백엔드로 사용하는 `SwiftVaultService`의 구체적인 구현체입니다.
public actor SwiftVaultKeychainService: SwiftVaultService {
    
    // MARK: - Public Properties
    
    public nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> {
        return changeStream
    }
    
    // MARK: - Private Properties
    
    private let keychainService: KeychainServiceProtocol
    private let logger: Logger
    private let keyPrefix: String
    private let serviceName = "SwiftVaultKeychainService"
    
    /// StoredObject 래퍼를 인코딩/디코딩하기 위한 내부 전용 직렬화 도구입니다.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private let (changeStream, changeContinuation): (AsyncStream<(key: String?, transactionID: UUID?)>, AsyncStream<(key: String?, transactionID: UUID?)>.Continuation)
    private var lastKnownKeys: Set<String> = []
    
    #if canImport(UIKit)
    private var foregroundObserver: ForegroundObserver?
    #endif
    
    // MARK: - Initialization
    
    public init(
        keychain: KeychainServiceProtocol? = nil,
        keyPrefix: String = "",
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked,
        loggerSubsystem: String = SwiftVault.Config.defaultLoggerSubsystem
    ) {
        self.keyPrefix = keyPrefix
        
        let config = KeychainConfiguration(
            service: "\(loggerSubsystem).\(serviceName)",
            accessGroup: accessGroup,
            accessibility: accessibility
        )
        self.keychainService = keychain ?? KeychainService(configuration: config)
        self.logger = Logger(subsystem: loggerSubsystem, category: serviceName)
        (self.changeStream, self.changeContinuation) = AsyncStream<(key: String?, transactionID: UUID?)>.makeStream()
        
        logger.info("Initialized with keyPrefix: '\(keyPrefix)', accessGroup: '\(String(describing: accessGroup))'")
        
        Task {
            await self.initializeStateAndStartObserving()
        }
    }
    
    deinit {
        changeContinuation.finish()
        logger.debug("Finished externalChanges stream.")
    }
    
    // MARK: - PersistenceService Implementation
    
    public func remove(forKey key: String) async throws {
        let prefixedKey = self.keyPrefix + key
        logger.debug("Attempting to remove value from keychain for key '\(prefixedKey)'")
        
        let result = await keychainService.delete(forKey: prefixedKey)
        
        switch result {
        case .success:
            logger.info("Successfully removed value from keychain for key '\(prefixedKey)'")
            lastKnownKeys.remove(prefixedKey)
            // 삭제 작업은 특정 트랜잭션 ID가 없으므로 nil을 전달합니다.
            changeContinuation.yield((key: key, transactionID: nil))
        case .failure(let keychainError):
            throw SwiftVaultError.deleteFailed(key: prefixedKey, underlyingError: keychainError)
        }
    }
    
    public func exists(forKey key: String) async -> Bool {
        let prefixedKey = self.keyPrefix + key
        let result = await keychainService.exists(forKey: prefixedKey)
        return result.value ?? false
    }
    
    public func clearAll() async throws {
        logger.warning("Attempting to clear all data managed by this instance (prefix: '\(self.keyPrefix)').")
        
        let allKeysResult = await keychainService.allKeys()
        switch allKeysResult {
        case .success(let keys):
            let keysToRemove = keys.filter { $0.hasPrefix(self.keyPrefix) }
            var firstError: SwiftVaultError?
            
            for key in keysToRemove {
                let deleteResult = await keychainService.delete(forKey: key)
                if case .failure(let error) = deleteResult, firstError == nil {
                    firstError = .deleteFailed(key: key, underlyingError: error)
                }
            }
            
            if let error = firstError { throw error }
            
            logger.info("Successfully cleared \(keysToRemove.count) keys with prefix '\(self.keyPrefix)'.")
            lastKnownKeys.removeAll()
            // 전체 삭제는 특정 키나 트랜잭션 ID가 없으므로 (nil, nil)을 전달합니다.
            changeContinuation.yield((key: nil, transactionID: nil))
            
        case .failure(let keychainError):
            throw SwiftVaultError.clearAllFailed(underlyingError: keychainError)
        }
    }

    // MARK: - Raw Data Handling
    
    public func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
        let prefixedKey = self.keyPrefix + key
        logger.debug("Attempting to save raw data to keychain for key '\(prefixedKey)' with transaction \(transactionID.uuidString.prefix(8))")

        let objectToStore = StoredObject(value: data, transactionID: transactionID)
        let dataToSave: Data
        do {
            dataToSave = try encoder.encode(objectToStore)
        } catch {
            throw SwiftVaultError.encodingFailed(type: "StoredObject", underlyingError: error)
        }
        
        let result = await keychainService.store(dataToSave, forKey: prefixedKey)
        
        switch result {
        case .success:
            logger.info("Successfully saved raw data to keychain for key '\(prefixedKey)'")
            if lastKnownKeys.contains(prefixedKey) == false {
                lastKnownKeys.insert(prefixedKey)
            }
            // 이 서비스가 직접 수행한 변경이므로, 트랜잭션 ID를 함께 전달합니다.
            changeContinuation.yield((key: key, transactionID: transactionID))
        case .failure(let keychainError):
            throw SwiftVaultError.writeFailed(key: prefixedKey, underlyingError: keychainError)
        }
    }
    
    public func loadData(forKey key: String) async throws -> Data? {
        let prefixedKey = self.keyPrefix + key
        logger.debug("Attempting to load raw data from keychain for key '\(prefixedKey)'")

        let result: KeychainResult<Data?> = await keychainService.retrieve(Data.self, forKey: prefixedKey)
        
        // ⭐️ [오류 수정] `result.value`는 `Data??` 타입이므로, 두 단계의 옵셔널을 모두 해제합니다.
        guard let optionalData = result.value, let encodedObject = optionalData else {
            // 키체인에 아이템이 없거나, 결과가 nil인 경우 모두 여기서 처리됩니다.
            return nil
        }
        
        // 이제 `encodedObject`는 non-optional `Data` 타입입니다.
        do {
            let storedObject = try decoder.decode(StoredObject.self, from: encodedObject)
            return storedObject.value
        } catch {
            logger.warning("Could not decode StoredObject for key '\(prefixedKey)'. Data might be in an old format or corrupted. Returning nil. Error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helper Methods
    
    private func checkForExternalChanges() async {
        logger.debug("Checking for external keychain changes...")
        guard let allKeys = (await keychainService.allKeys()).value else {
            logger.warning("Could not retrieve all keys to check for external changes. Skipping check.")
            return
        }
        
        let currentKeys = Set(allKeys.filter { $0.hasPrefix(self.keyPrefix) })
        let addedKeys = currentKeys.subtracting(lastKnownKeys)
        let removedKeys = lastKnownKeys.subtracting(currentKeys)
        
        if !addedKeys.isEmpty || !removedKeys.isEmpty {
            logger.info("External changes detected. Added: \(addedKeys.count), Removed: \(removedKeys.count).")
            // 키체인 외부 변경 감지는 키 목록 비교에 의존하므로, 변경된 내용의 transactionID를 알 수 없습니다.
            // 따라서 transactionID는 nil로 전달하여, 수신 측에서 무조건 리로드하도록 합니다.
            if let changedKey = addedKeys.union(removedKeys).first {
                changeContinuation.yield((key: String(changedKey.dropFirst(self.keyPrefix.count)), transactionID: nil))
            }
        }
        
        self.lastKnownKeys = currentKeys
    }
    
    private func initializeStateAndStartObserving() async {
        if let keys = (await keychainService.allKeys()).value {
            self.lastKnownKeys = Set(keys.filter { $0.hasPrefix(self.keyPrefix) })
            logger.debug("Initial keychain state loaded with \(self.lastKnownKeys.count) keys.")
        } else {
            logger.warning("Could not load initial state of keychain keys.")
        }
        
        #if canImport(UIKit)
        self.foregroundObserver = await ForegroundObserver { [weak self] in
            Task { [weak self] in
                await self?.checkForExternalChanges()
            }
        }
        #else
        logger.info("UIKit is not available. External change detection via foreground notification is disabled.")
        #endif
    }
}
