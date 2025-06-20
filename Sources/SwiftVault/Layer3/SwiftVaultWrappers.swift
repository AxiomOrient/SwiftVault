// SwiftVault/Layer3/SwiftVaultWrappers.swift

import SwiftUI
import OSLog
import Foundation

// MARK: - Fatal Error Helper
internal func fatalErrorOnSetupFailure(_ error: Error, key: String, storageTypeDescription: String) -> Never {
    let errorMessage = """
    [SwiftVault] FAILED TO INITIALIZE PERSISTED STORAGE FOR KEY: "\(key)" using \(storageTypeDescription).
    This is a critical setup error, and the application cannot continue.
    """
    let logger = Logger(subsystem: SwiftVault.Config.defaultLoggerSubsystem, category: "VaultStored.Setup")
    logger.critical("\(errorMessage) Underlying Error: \(error.localizedDescription, privacy: .public)")
    fatalError(errorMessage)
}

// MARK: - VaultStorable Protocol

public protocol VaultStorable {
    associatedtype Value: AnyCodable & Equatable
    static var key: String { get }
    static var defaultValue: Value { get }
    static var storageType: SwiftVaultStorageType { get }
    
    static var encoder: JSONEncoder { get }
    static var decoder: JSONDecoder { get }
    
    static func configure(builder: DataMigrator<Value>.Builder)
}

public extension VaultStorable {
    static var key: String {
        return String(describing: Self.self)
    }
    
    static var storageType: SwiftVaultStorageType {
        .userDefaults()
    }
    
    static var encoder: JSONEncoder { JSONEncoder() }
    static var decoder: JSONDecoder { JSONDecoder() }
    
    static func configure(builder: DataMigrator<Value>.Builder) {}
}

// MARK: - @VaultStored Property Wrapper

@MainActor
@propertyWrapper
public struct VaultStored<Value: AnyCodable & Equatable>: DynamicProperty {
    
    @StateObject private var storage: VaultDataStorage<Value>
    
    public var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
    
    public var projectedValue: Binding<Value> {
        Binding(get: { wrappedValue }, set: { wrappedValue = $0 })
    }
    
    public init<D: VaultStorable>(_ definition: D.Type) where D.Value == Value {
        _storage = StateObject(wrappedValue: VaultManager.shared.storage(for: definition))
    }
}

// MARK: - VaultDataStorage (Internal Engine)

@MainActor
internal final class VaultDataStorage<Value: AnyCodable & Equatable>: ObservableObject {
    
    @Published var value: Value {
        didSet {
            if value != oldValue {
                saveValueWithDebounce()
            }
        }
    }
    
    private let key: String
    private let service: SwiftVaultService
    private let migrator: DataMigrator<Value>
    private let logger: Logger
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    private var debounceTask: Task<Void, Never>?
    private var monitoringTask: Task<Void, Never>?
    private var loadingTask: Task<Void, Never>?
    
    private var lastTransactionID: UUID?
    
    /// 비동기 초기화 작업의 완료를 추적하기 위한 Task 핸들입니다.
    private var _initializationTask: Task<Void, Never>?
    
    var initializationTask: Task<Void, Never> {
        if let task = _initializationTask {
            return task
        }
        
        let task = Task {
            await self.loadInitialValue()
            self.startExternalChangesMonitoring()
        }
        _initializationTask = task
        return task
    }
    
    init(key: String,
         defaultValue: Value,
         service: SwiftVaultService,
         migrator: DataMigrator<Value>,
         encoder: JSONEncoder,
         decoder: JSONDecoder)
    {
        self.key = key
        self.service = service
        self.migrator = migrator
        self.encoder = encoder
        self.decoder = decoder
        self._value = .init(initialValue: defaultValue)
        self.logger = Logger(subsystem: SwiftVault.Config.defaultLoggerSubsystem, category: "VaultDataStorage")
        
        // 초기화 완료 후 비동기 작업 시작
        Task {
            _ = self.initializationTask // 지연 초기화 트리거
        }
    }
    
    deinit {
        debounceTask?.cancel()
        monitoringTask?.cancel()
        loadingTask?.cancel()
        _initializationTask?.cancel()
    }
    
    private func loadInitialValue() async {
        guard loadingTask == nil else { return }
        
        loadingTask = Task {
            defer { loadingTask = nil }
            if let initialValue = await loadAndMigrateIfNeeded() {
                if self.value != initialValue {
                    self.value = initialValue
                }
            }
        }
        await loadingTask?.value
    }
    
    private func saveValueWithDebounce() {
        debounceTask?.cancel()
        
        debounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(300))
                await performSave()
            } catch is CancellationError {
            } catch {
                logger.error("Failed to save value after debounce for key '\(self.key, privacy: .public)': \(error.localizedDescription)")
            }
        }
    }
    
    private nonisolated func performSave() async {
        do {
            let transactionID = UUID()
            let currentValue = await readCurrentValue()
            let dataToSave = try encoder.encode(currentValue)
            
            try await service.saveData(dataToSave, forKey: key, transactionID: transactionID)
            
            await MainActor.run {
                self.lastTransactionID = transactionID
            }
            logger.debug("Successfully saved value for key '\(self.key, privacy: .public)'.")
        } catch {
            logger.error("Error during background save for key '\(self.key, privacy: .public)': \(error.localizedDescription)")
        }
    }
    
    private func startExternalChangesMonitoring() {
        monitoringTask = Task {
            for await (changedKey, transactionID) in service.externalChanges {
                if Task.isCancelled { break }
                
                await self.processExternalChange(changedKey: changedKey, transactionID: transactionID)
            }
        }
    }
    
    private func processExternalChange(changedKey: String?, transactionID: UUID?) async {
        if let transactionID, transactionID == self.lastTransactionID {
            logger.debug("Ignoring echo notification via transaction ID for key '\(self.key, privacy: .public)'.")
            return
        }
        
        guard changedKey == nil || changedKey == self.key else { return }
        guard loadingTask == nil else {
            logger.debug("Load already in progress. Ignoring external change notification.")
            return
        }
        
        loadingTask = Task {
            defer { loadingTask = nil }
            
            let dataOnDisk = try? await service.loadData(forKey: key)
            let dataInMemory = try? encoder.encode(self.value)
            
            if dataOnDisk != dataInMemory {
                logger.info("Data for key '\(self.key)' is out of sync. Reloading value.")
                if let reloadedValue = await self.loadAndMigrateIfNeeded() {
                    if self.value != reloadedValue {
                        self.value = reloadedValue
                    }
                }
            } else {
                logger.debug("Ignoring notification for key '\(self.key, privacy: .public)' as data is already in sync.")
            }
        }
        await loadingTask?.value
    }
    
    private func readCurrentValue() async -> Value {
        await MainActor.run { self.value }
    }
    
    private func loadAndMigrateIfNeeded() async -> Value? {
        await Task.detached { [weak self] in
            guard let self else { return nil }
            
            guard let data = try? await self.service.loadData(forKey: self.key) else {
                return nil
            }
            
            do {
                return try self.decoder.decode(Value.self, from: data)
            } catch {
                self.logger.debug("Direct decoding failed for key '\(self.key)', attempting migration. Error: \(error.localizedDescription)")
            }
            
            do {
                let (migratedData, wasMigrated) = try await self.migrator.migrate(data: data)
                
                if wasMigrated {
                    self.logger.info("Successfully migrated data for key '\(self.key, privacy: .public)'.")
                    let transactionID = UUID()
                    try await self.service.saveData(migratedData, forKey: self.key, transactionID: transactionID)
                    
                    await MainActor.run {
                        self.lastTransactionID = transactionID
                    }
                }
                
                return try self.decoder.decode(Value.self, from: migratedData)
            } catch {
                self.logger.error("Failed to migrate and decode data for key '\(self.key, privacy: .public)': \(error.localizedDescription)")
                return nil
            }
        }.value
    }
}
