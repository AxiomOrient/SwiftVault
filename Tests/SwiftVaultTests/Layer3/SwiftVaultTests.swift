import Testing
@testable import SwiftVault
import Foundation

/// `@VaultStored`의 핵심 로직을 담당하는 `VaultDataStorage`를 검증하는 테스트 스위트입니다.
@Suite("VaultDataStorage Tests")
@MainActor
struct VaultDataStorageTests {

    // MARK: - Mocking & Models

    /// 테스트용 Mock 서비스입니다.
    private actor MockStorageService: SwiftVaultService {
        var storage: [String: Data] = [:]
        private(set) var saveCallCount = 0
        private(set) var loadCallCount = 0
        
        private let changesContinuation: AsyncStream<(key: String?, transactionID: UUID?)>.Continuation
        nonisolated let externalChanges: AsyncStream<(key: String?, transactionID: UUID?)>

        init() {
            var continuation: AsyncStream<(key: String?, transactionID: UUID?)>.Continuation!
            self.externalChanges = AsyncStream { continuation = $0 }
            self.changesContinuation = continuation
        }
        
        func triggerExternalChange(forKey key: String?, transactionID: UUID = UUID()) {
            changesContinuation.yield((key: key, transactionID: transactionID))
        }
        
        /// Mock 저장소에 데이터를 직접 설정하기 위한 헬퍼 메서드입니다.
        func setData(_ data: Data, forKey key: String) {
            storage[key] = data
        }

        // --- SwiftVaultService Protocol Conformance ---
        
        func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
            storage[key] = data
            saveCallCount += 1
        }
        
        func loadData(forKey key: String) async throws -> Data? {
            loadCallCount += 1
            return storage[key]
        }
        
        func remove(forKey key: String) async throws { storage[key] = nil }
        func exists(forKey key: String) async -> Bool { storage[key] != nil }
        func clearAll() async throws { storage.removeAll() }
    }

    private struct TestModel: Codable, Equatable, Sendable {
        var value: String
    }
    
    // MARK: - Test Setup
    
    private let testKey = "testKey"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - Test Cases
    
    /// **Intent:** 저장된 값이 있을 때 해당 값으로 올바르게 초기화되는지 검증합니다.
    @Test("Initializes with saved value when data exists")
    func testInitializationWithSavedValue() async throws {
        // Arrange
        let service = MockStorageService()
        let savedValue = TestModel(value: "saved")
        let savedData = try encoder.encode(savedValue)
        try await service.saveData(savedData, forKey: testKey, transactionID: UUID())
        
        let migrator = DataMigrator.Builder(targetType: TestModel.self).build()

        // Act
        let storage = VaultDataStorage(key: testKey, defaultValue: TestModel(value: "default"), service: service, migrator: migrator, encoder: encoder, decoder: decoder)
        try await Task.sleep(nanoseconds: 100_000_000) // 초기 로드 대기

        // Assert
        #expect(storage.value == savedValue, "Value should be the saved value.")
    }

    /// **Intent:** 값을 변경했을 때, 300ms 디바운스 후 `saveData`가 한 번만 호출되는지 검증합니다.
    @Test("Saves value after debounce duration")
    func testSaveAfterDebounce() async throws {
        // Arrange
        let service = MockStorageService()
        let migrator = DataMigrator.Builder(targetType: TestModel.self).build()
        let storage = VaultDataStorage(key: testKey, defaultValue: TestModel(value: "initial"), service: service, migrator: migrator, encoder: encoder, decoder: decoder)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Act
        storage.value = TestModel(value: "updated")
        
        // Assert: 즉시 저장되지 않음
        var saveCount = await service.saveCallCount
        #expect(saveCount == 0, "Save should not be called immediately.")
        
        // 300ms 이상 대기
        try await Task.sleep(nanoseconds: 400_000_000)
        
        saveCount = await service.saveCallCount
        #expect(saveCount == 1, "Save should be called once after the debounce period.")
        
        let loadedData = try await service.loadData(forKey: "testKey")
        let unwrappedData = try #require(loadedData)
        let loadedModel = try decoder.decode(TestModel.self, from: unwrappedData)
        #expect(loadedModel.value == "updated")
    }
    
    /// **Intent:** 디바운스 시간 내에 값이 여러 번 변경되면, 최종 값으로 `saveData`가 한 번만 호출되는지 검증합니다.
    @Test("Saves only the final value after multiple rapid changes")
    func testMultipleChangesTriggerSingleSave() async throws {
        // Arrange
        let service = MockStorageService()
        let migrator = DataMigrator.Builder(targetType: TestModel.self).build()
        let storage = VaultDataStorage(key: testKey, defaultValue: TestModel(value: "initial"), service: service, migrator: migrator, encoder: encoder, decoder: decoder)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Act
        storage.value = TestModel(value: "change 1")
        try await Task.sleep(nanoseconds: 50_000_000)
        storage.value = TestModel(value: "change 2")
        try await Task.sleep(nanoseconds: 50_000_000)
        storage.value = TestModel(value: "final change")

        // Assert: 아직 저장되지 않음
        var saveCount = await service.saveCallCount
        #expect(saveCount == 0, "Save should not have been called yet.")

        try await Task.sleep(nanoseconds: 400_000_000) // 마지막 변경 후 디바운스 시간까지 대기

        saveCount = await service.saveCallCount
        #expect(saveCount == 1, "Save should be called only once.")

        let loadedData = try await service.loadData(forKey: "testKey")
        let unwrappedData = try #require(loadedData)
        let loadedModel = try decoder.decode(TestModel.self, from: unwrappedData)
        #expect(loadedModel.value == "final change", "The final value should be saved.")
    }

    /// **Intent:** `externalChanges` 스트림 이벤트 수신 시 값이 자동으로 리로드되는지 검증합니다.
    @Test("Reloads value on external change notification")
    func testReloadOnExternalChange() async throws {
        // Arrange
        let service = MockStorageService()
        let migrator = DataMigrator.Builder(targetType: TestModel.self).build()
        let storage = VaultDataStorage(key: testKey, defaultValue: TestModel(value: "initial"), service: service, migrator: migrator, encoder: encoder, decoder: decoder)
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Act
        // 외부에서 직접 데이터를 변경하는 상황 시뮬레이션
        let externalValue = TestModel(value: "external update")
        let externalData = try encoder.encode(externalValue)
        try await service.saveData(externalData, forKey: testKey, transactionID: UUID())
        
        // 외부 변경 알림 트리거
        await service.triggerExternalChange(forKey: testKey)
        
        // 리로드 대기
        try await Task.sleep(nanoseconds: 100_000_000)
        
        // Assert
        #expect(storage.value == externalValue, "Value should be updated to the externally changed value.")
    }
    
    /// **Intent:** `DataMigrator`가 주입되었을 때, 구버전 데이터를 최신 버전으로 마이그레이션하는지 검증합니다.
    @Test("Performs migration on load when migrator is provided")
    func testMigrationOnLoad() async throws {
        // Arrange
        struct V1: Codable, Sendable, Equatable { let name: String }
        struct V2: Codable, Sendable, Equatable { let fullName: String }

        let service = MockStorageService()
        let v1Data = try JSONEncoder().encode(V1(name: "Old Data"))
        await service.setData(v1Data, forKey: "migratedKey")

        let migrator = DataMigrator.Builder(targetType: V2.self)
            .register(from: V1.self, to: V2.self) { v1 in
                V2(fullName: "Migrated: \(v1.name)")
            }
            .build()
            
        // Act
        let storage = VaultDataStorage(key: "migratedKey", defaultValue: V2(fullName: ""), service: service, migrator: migrator, encoder: JSONEncoder(), decoder: JSONDecoder())
        try await Task.sleep(nanoseconds: 100_000_000) // 초기 로드 및 마이그레이션 대기

        // Assert
        #expect(storage.value.fullName == "Migrated: Old Data", "Value should be migrated from V1 to V2.")
        
        let saveCount = await service.saveCallCount
        #expect(saveCount == 1, "Save should be called once with the migrated data.")
    }
}
