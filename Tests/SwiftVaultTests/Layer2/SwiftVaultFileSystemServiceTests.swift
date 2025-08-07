import Testing
@testable import SwiftVault
import Foundation

/// `SwiftVaultFileSystemService`의 동작을 검증하는 테스트 스위트입니다.
@Suite("SwiftVaultFileSystemService Tests")
@MainActor
struct SwiftVaultFileSystemServiceTests {

    // MARK: - Test Properties
    
    private struct TestModel: Codable, Equatable, Sendable {
        let id: Int
        let name: String
    }
    
    private let testKey = "fileSystemTest"
    private let testModel = TestModel(id: 42, name: "FileSystem")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    // MARK: - Private Helpers
    
    private func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dirURL = tempDir.appendingPathComponent("FileSystemServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        return dirURL
    }
    
    // MARK: - Test Cases

    /// **Intent:** `saveData`와 `loadData`가 파일 시스템에 원시 데이터를 정상적으로 저장하고 불러오는지 검증합니다.
    @Test("Save and load raw Data from file system")
    func testSaveAndLoadData() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))
        let originalData = try encoder.encode(testModel)
        
        // Act
        try await service.saveData(originalData, forKey: testKey, transactionID: UUID())
        let loadedData = try await service.loadData(forKey: testKey)
        
        // Assert
        let unwrappedData = try #require(loadedData)
        let loadedModel = try decoder.decode(TestModel.self, from: unwrappedData)
        #expect(loadedModel == testModel)
        
        let fileURL = testDirectoryURL.appendingPathComponent(testKey)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    /// **Intent:** `remove` 메서드가 지정된 파일을 파일 시스템에서 올바르게 삭제하는지 검증합니다.
    @Test("Remove file from file system")
    func testRemove() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))
        let originalData = try encoder.encode(testModel)
        try await service.saveData(originalData, forKey: testKey, transactionID: UUID())
        
        // Act
        try await service.remove(forKey: testKey)
        
        // Assert
        let loadedData = try await service.loadData(forKey: testKey)
        #expect(loadedData == nil)
        
        let fileURL = testDirectoryURL.appendingPathComponent(testKey)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
    
    /// **Intent:** 초기화 시 `baseDirectory`가 존재하지 않으면 자동으로 생성되는지 검증합니다.
    @Test("Initialization creates base directory if needed")
    func testDirectoryCreationOnInit() throws {
        // Arrange
        let nonExistentDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("non-existent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: nonExistentDirectoryURL) }
        
        #expect(!FileManager.default.fileExists(atPath: nonExistentDirectoryURL.path), "Directory should not exist before initialization.")

        // Act
        _ = try SwiftVaultFileSystemService(baseDirectory: .url(nonExistentDirectoryURL))
        
        // Assert
        #expect(FileManager.default.fileExists(atPath: nonExistentDirectoryURL.path), "Directory should exist after initialization.")
    }
    
    /// **Intent:** `clearAll` 메서드가 `baseDirectory`의 모든 내용을 삭제하는지 검증합니다.
    @Test("Clear all files in base directory")
    func testClearAll() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))
        let data = try encoder.encode(testModel)
        try await service.saveData(data, forKey: "key1", transactionID: UUID())
        try await service.saveData(data, forKey: "key2", transactionID: UUID())
        
        // Act
        try await service.clearAll()
        
        // Assert
        let contents = try FileManager.default.contentsOfDirectory(atPath: testDirectoryURL.path)
        #expect(contents.isEmpty, "Base directory should be empty after clearAll.")
    }
    
    /// **Intent:** 외부에서 파일이 직접 생성되었을 때, `externalChanges` 스트림이 해당 파일 키를 방출하는지 검증합니다.
    @Test("External changes stream detects file creation")
    func testExternalChangesFileCreation() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))
        
        let externalFileKey = "externalFile"
        let externalFileURL = testDirectoryURL.appendingPathComponent(externalFileKey)
        
        let task = Task {
            for await (key, _) in service.externalChanges {
                if key == externalFileKey { return key }
            }
            return nil
        }
        
        // Act
        try await Task.sleep(nanoseconds: 200_000_000)
        FileManager.default.createFile(atPath: externalFileURL.path, contents: "external data".data(using: .utf8))
        
        // Assert
        let result = await withTimeout(seconds: 2) { await task.value }
        let receivedKeyEvent = try #require(result)
        
        #expect(receivedKeyEvent == externalFileKey)
        task.cancel()
    }

    /// **Intent:** 외부에서 파일이 직접 삭제되었을 때, `externalChanges` 스트림이 해당 파일 키를 방출하는지 검증합니다.
    @Test("External changes stream detects file deletion")
    func testExternalChangesFileDeletion() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }
        
        let externalFileKey = "deletableFile"
        let externalFileURL = testDirectoryURL.appendingPathComponent(externalFileKey)
        FileManager.default.createFile(atPath: externalFileURL.path, contents: "some data".data(using: .utf8))

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))

        let task = Task {
            for await (key, _) in service.externalChanges {
                if key == externalFileKey { return key }
            }
            return nil
        }

        // Act
        try await Task.sleep(nanoseconds: 200_000_000)
        try FileManager.default.removeItem(at: externalFileURL)

        // Assert
        let result = await withTimeout(seconds: 2) { await task.value }
        let receivedKeyEvent = try #require(result)
        
        #expect(receivedKeyEvent == externalFileKey)
        task.cancel()
    }

    /// **Intent:** 외부에서 파일이 직접 이동되었을 때, `externalChanges` 스트림이 이전 키와 새 키를 모두 방출하는지 검증합니다.
    @Test("External changes stream detects file move")
    func testExternalChangesFileMove() async throws {
        // Arrange
        let testDirectoryURL = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectoryURL) }

        let oldKey = "oldFile"
        let newKey = "newFile"
        let oldURL = testDirectoryURL.appendingPathComponent(oldKey)
        let newURL = testDirectoryURL.appendingPathComponent(newKey)
        FileManager.default.createFile(atPath: oldURL.path, contents: "move data".data(using: .utf8))

        let service = try SwiftVaultFileSystemService(baseDirectory: .url(testDirectoryURL))

        let task = Task {
            var receivedKeys = Set<String>()
            for await (key, _) in service.externalChanges {
                if let key, [oldKey, newKey].contains(key) {
                    receivedKeys.insert(key)
                    if receivedKeys.count == 2 {
                        return receivedKeys
                    }
                }
            }
            return receivedKeys
        }
        
        // Act
        try await Task.sleep(nanoseconds: 200_000_000)
        try FileManager.default.moveItem(at: oldURL, to: newURL)
        
        // Assert
        let result = await withTimeout(seconds: 2) { await task.value }
        let receivedKeySet = try #require(result)
        
        #expect(receivedKeySet.contains(oldKey))
        #expect(receivedKeySet.contains(newKey))
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
        
        // 첫 번째로 완료되는 작업의 결과를 기다립니다.
        if let result = await group.next() {
            // 결과가 있으면 다른 모든 작업을 취소하고 결과를 반환합니다.
            group.cancelAll()
            return result
        }
        
        // 두 작업 모두 결과를 반환하지 않은 드문 경우입니다.
        return nil
    }
}
