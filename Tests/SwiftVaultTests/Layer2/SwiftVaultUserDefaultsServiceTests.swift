import Testing
@testable import SwiftVault
import Foundation

/// `SwiftVaultUserDefaultsService`의 동작을 검증하는 테스트 스위트입니다.
/// 실제 UserDefaults를 사용하며, 각 테스트는 고유한 suiteName으로 격리됩니다.
@Suite("SwiftVaultUserDefaultsService Integration Tests")
@MainActor
struct SwiftVaultUserDefaultsServiceTests {
    
    // MARK: - Test Properties
    
    private struct TestModel: Codable, Equatable, Sendable {
        let id: Int
        let name: String
    }
    
    private let testKey = "testModel"
    private let testModel = TestModel(id: 1, name: "Gemini")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Teardown Helper
    
    /// 테스트 종료 시 생성된 UserDefaults suite를 정리합니다.
    private func cleanupUserDefaults(suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
    
    // MARK: - Test Cases
    
    /// **Intent:** `saveData`와 `loadData`를 사용하여 `Codable` 객체를 정상적으로 저장하고 불러오는지 검증합니다.
    @Test("Save and load Codable object")
    func testSaveAndLoad() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        let originalData = try encoder.encode(testModel)
        
        // Act
        try await service.saveData(originalData, forKey: testKey, transactionID: UUID())
        let loadedData = try await service.loadData(forKey: testKey)
        
        // Assert
        let unwrappedData = try #require(loadedData)
        let loadedModel = try decoder.decode(TestModel.self, from: unwrappedData)
        #expect(loadedModel == testModel, "Loaded model should be equal to the saved model.")
    }
    
    /// **Intent:** `remove` 메서드가 지정된 키의 데이터를 올바르게 삭제하는지 검증합니다.
    @Test("Remove object for key")
    func testRemove() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        let originalData = try encoder.encode(testModel)
        try await service.saveData(originalData, forKey: testKey, transactionID: UUID())
        
        // Act
        try await service.remove(forKey: testKey)
        let loadedData = try await service.loadData(forKey: testKey)
        
        // Assert
        #expect(loadedData == nil, "Model should be nil after being removed.")
    }
    
    /// **Intent:** `exists` 메서드가 키 존재 여부를 정확하게 반환하는지 검증합니다.
    @Test("Check for existence of an object")
    func testExists() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        // Assert: Before saving
        #expect(await service.exists(forKey: testKey) == false, "Should not exist before saving.")
        
        // Act
        let originalData = try encoder.encode(testModel)
        try await service.saveData(originalData, forKey: testKey, transactionID: UUID())
        
        // Assert: After saving
        #expect(await service.exists(forKey: testKey) == true, "Should exist after saving.")
        
        try await service.remove(forKey: testKey)
        
        // Assert: After removing
        #expect(await service.exists(forKey: testKey) == false, "Should not exist after removal.")
    }
    
    /// **Intent:** `clearAll` 메서드가 해당 `UserDefaults` suite의 모든 데이터를 삭제하는지 검증합니다.
    @Test("Clear all data")
    func testClearAll() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        let data1 = try encoder.encode(testModel)
        let data2 = try encoder.encode(TestModel(id: 2, name: "Google"))
        try await service.saveData(data1, forKey: "key1", transactionID: UUID())
        try await service.saveData(data2, forKey: "key2", transactionID: UUID())
        
        // Act
        try await service.clearAll()
        
        // Assert
        #expect(await service.exists(forKey: "key1") == false)
        #expect(await service.exists(forKey: "key2") == false)
    }
    
    /// **Intent:** 손상된 StoredObject를 디코딩하려고 할 때 `loadData`가 nil을 반환하는지 검증합니다.
    @Test("Loading corrupted StoredObject returns nil")
    func testCorruptedStoredObject() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        // Act: StoredObject로 감싸지지 않은, 완전히 손상된 데이터를 저장합니다.
        let corruptedData = "this is not valid json".data(using: .utf8)!
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.set(corruptedData, forKey: testKey)
        
        // Assert: loadData가 StoredObject 디코딩에 실패하고 nil을 반환해야 합니다.
        let loadedData = try await service.loadData(forKey: testKey)
        #expect(loadedData == nil, "Loading a value that isn't a StoredObject should result in nil.")
    }
    
    /// **Intent:** 외부(다른 서비스 인스턴스)에서 `UserDefaults`가 변경되었을 때, `externalChanges` 스트림이 이벤트를 방출하는지 검증합니다.
    @Test("External changes stream receives event on change")
    func testExternalChangesStreamReceivesEvent() async throws {
        // Arrange
        let suiteName = UUID().uuidString
        let service1 = SwiftVaultUserDefaultsService(suiteName: suiteName)
        let service2 = SwiftVaultUserDefaultsService(suiteName: suiteName)
        defer { cleanupUserDefaults(suiteName: suiteName) }
        
        let task = Task {
            for await _ in service1.externalChanges {
                return true
            }
            return false
        }
        
        // Act
        try await Task.sleep(nanoseconds: 100_000_000)
        let data = try encoder.encode(testModel)
        try await service2.saveData(data, forKey: "someKey", transactionID: UUID())
        
        // Assert
        let result = await withTimeout(seconds: 2) { await task.value }
        #expect(result == true, "The operation should return true, indicating an event was received.")
        
        task.cancel()
    }
}

/// 지정된 시간 내에 비동기 작업이 완료되도록 하고, 타임아웃 시 nil을 반환하는 헬퍼 함수입니다.
private func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async -> T?
) async -> T? {
    await withTaskGroup(of: T?.self, returning: T?.self) { group in
        group.addTask {
            await operation()
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil // Timeout marker
        }
        
        if let result = await group.next() {
            group.cancelAll()
            return result
        }
        return nil
    }
}
