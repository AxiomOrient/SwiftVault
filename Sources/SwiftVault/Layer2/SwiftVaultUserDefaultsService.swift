// SwiftVault/Layer2/SwiftVaultUserDefaultsService.swift

import Foundation
import Combine
import OSLog

/// UserDefaults의 모든 I/O와 알림 구독을 안전하게 격리하여 처리하는 전용 Worker 액터입니다.
private actor UserDefaultsWorker {
    private let userDefaults: UserDefaults
    private var notificationTask: Task<Void, Never>?

    init(suiteName: String?) {
        if let sn = suiteName, let specific = UserDefaults(suiteName: sn) {
            self.userDefaults = specific
        } else {
            self.userDefaults = .standard
        }
    }
    
    deinit {
        notificationTask?.cancel()
    }
    
    /// 외부 변경 알림 구독을 시작합니다.
    func startObserving(continuation: AsyncStream<(key: String?, transactionID: UUID?)>.Continuation) {
        notificationTask = Task {
            let stream = NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification, object: nil)
            for await _ in stream {
                if Task.isCancelled { break }
                continuation.yield((key: nil, transactionID: nil))
            }
        }
    }

    // MARK: - I/O Operations
    
    func removeObject(forKey key: String) {
        userDefaults.removeObject(forKey: key)
    }

    func objectExists(forKey key: String) -> Bool {
        userDefaults.object(forKey: key) != nil
    }

    func removePersistentDomain(forName domainName: String) {
        userDefaults.removePersistentDomain(forName: domainName)
    }

    func set(_ data: Data, forKey key: String) {
        userDefaults.set(data, forKey: key)
    }

    func data(forKey key: String) -> Data? {
        userDefaults.data(forKey: key)
    }
    
    func domainName(from suiteName: String?) -> String? {
        if self.userDefaults == .standard {
            return Bundle.main.bundleIdentifier
        } else {
            return suiteName
        }
    }
}


/// `UserDefaults`를 백엔드로 사용하는 `SwiftVaultService`의 구체적인 구현체입니다.
public actor SwiftVaultUserDefaultsService: SwiftVaultService {
    
    // MARK: - Public Properties
    
    public nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> {
        return changeStream
    }
    
    // MARK: - Private Properties
    
    private let worker: UserDefaultsWorker
    private let logger: Logger
    private let suiteName: String?
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private let (changeStream, changeContinuation): (AsyncStream<(key: String?, transactionID: UUID?)>, AsyncStream<(key: String?, transactionID: UUID?)>.Continuation)
    
    // MARK: - Initialization
    
    public init(
        suiteName: String? = nil,
        loggerSubsystem: String = SwiftVault.Config.defaultLoggerSubsystem
    ) {
        self.suiteName = suiteName
        self.logger = Logger(subsystem: loggerSubsystem, category: "SwiftVaultUserDefaultsService")
        
        (self.changeStream, self.changeContinuation) = AsyncStream<(key: String?, transactionID: UUID?)>.makeStream()
        
        // 1. Worker를 먼저 초기화합니다.
        self.worker = UserDefaultsWorker(suiteName: suiteName)
        
        // 2. 초기화가 끝난 후, 별도의 Task를 통해 Worker의 알림 구독을 시작시킵니다.
        Task {
            await worker.startObserving(continuation: self.changeContinuation)
        }
    }
    
    deinit {
        changeContinuation.finish()
    }
    
    // MARK: - PersistenceService Implementation
    
    public func remove(forKey key: String) async throws {
        logger.debug("Attempting to remove value for key '\(key)'")
        await worker.removeObject(forKey: key)
    }
    
    public func exists(forKey key: String) async -> Bool {
        await worker.objectExists(forKey: key)
    }
    
    public func clearAll() async throws {
        logger.warning("Attempting to clear all data from this UserDefaults suite.")
        
        guard let domainName = await worker.domainName(from: self.suiteName) else {
            let errorMessage = "Cannot determine domain name to clear UserDefaults."
            logger.error("\(errorMessage)")
            throw SwiftVaultError.clearAllFailed(underlyingError: NSError(domain: "SwiftVault", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        }
        
        await worker.removePersistentDomain(forName: domainName)
    }
    
    // MARK: - Raw Data Handling
    
    public func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
        logger.debug("Attempting to save raw data for key '\(key)' with transaction \(transactionID.uuidString.prefix(8))")
        
        let objectToStore = StoredObject(value: data, transactionID: transactionID)
        do {
            let encodedObject = try encoder.encode(objectToStore)
            await worker.set(encodedObject, forKey: key)
        } catch {
            throw SwiftVaultError.encodingFailed(type: "StoredObject", underlyingError: error)
        }
    }
    
    public func loadData(forKey key: String) async throws -> Data? {
        logger.debug("Attempting to load raw data for key '\(key)'")
        
        guard let encodedObject = await worker.data(forKey: key) else {
            return nil
        }
        
        do {
            let storedObject = try decoder.decode(StoredObject.self, from: encodedObject)
            return storedObject.value
        } catch {
            logger.warning("Could not decode StoredObject for key '\(key)'. Data might be in an old format or corrupted. Returning nil. Error: \(error.localizedDescription)")
            return nil
        }
    }
}
