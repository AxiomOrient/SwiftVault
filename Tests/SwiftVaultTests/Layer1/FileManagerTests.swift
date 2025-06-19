import Testing
import Foundation
@testable import SwiftVault // 테스트할 모듈을 import 합니다.

/// `FileManager.Path` 및 `FileManager` 확장의 동작을 검증하는 테스트 스위트입니다.
@Suite("FileManager Extensions & Path Utilities")
struct FileManagerTests {
    
    // MARK: - Test Lifecycle Helper
    
    /// 테스트 실행을 위한 임시 디렉토리를 생성하고, 테스트가 끝나면 자동으로 정리하는 헬퍼 함수입니다.
    /// - Parameter work: 임시 디렉토리의 URL을 받아 테스트 로직을 실행하는 클로저입니다.
    private func withTemporaryDirectory(
        _ work: (URL) throws -> Void
    ) throws {
        let fileManager = FileManager.default
        let tempDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("FileManagerTests_\(UUID().uuidString)")
        
        try fileManager.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        
        // 이 클로저를 벗어날 때 항상 디렉토리를 삭제하도록 보장합니다.
        defer {
            try? fileManager.removeItem(at: tempDirectoryURL)
        }
        
        try work(tempDirectoryURL)
    }
    
    // MARK: - Path Creation Tests
    
    /// `FileManager.Path`의 각 케이스가 올바른 시스템 경로 URL을 생성하는지 검증합니다.
    /// - Intent: 각 `Path` 열거형 케이스가 의도한 디렉토리 내에 정확한 URL을 구성하는지 확인합니다.
    /// - Given: `.document`, `.cache`, `.applicationSupport`, `.custom`, `.url` 케이스.
    /// - When: 각 케이스의 `.url()` 메서드를 호출합니다.
    /// - Then: 반환된 URL의 경로 문자열이 예상된 기본 경로와 파일명을 포함해야 합니다.
    @Test("Path enum creates correct URLs for each case")
    func testPathURLCreation() throws {
        // Arrange
        let docPath = FileManager.Path.document("test.txt")
        let cachePath = FileManager.Path.cache("temp/file")
        let supportPath = FileManager.Path.applicationSupport("settings.json")
        let customPath = FileManager.Path.custom("/tmp/absolute.log")
        let urlPath = try #require(URL(string: "file:///var/mobile"))
        let urlPathWrapper = FileManager.Path.url(urlPath)
        
        // Act & Assert
        #expect(try docPath.url().path.hasSuffix("/Documents/test.txt"))
        #expect(try cachePath.url().path.hasSuffix("/Caches/temp/file"))
        #expect(try supportPath.url().path.hasSuffix("/Application Support/settings.json"))
        #expect(try customPath.url().path == "/tmp/absolute.log")
        #expect(try urlPathWrapper.url().path == "/var/mobile")
    }
    
    // MARK: - Directory Operations
    
    /// `createDirectoryIfNeeded()`가 새로운 디렉토리를 성공적으로 생성하는지 검증합니다.
    /// - Intent: 존재하지 않는 경로에 대해 디렉토리를 생성하는 기능을 확인합니다.
    /// - Given: 존재하지 않는 디렉토리 경로.
    /// - When: `createDirectoryIfNeeded()`를 호출합니다.
    /// - Then: 해당 경로에 디렉토리가 실제로 생성되어야 합니다.
    @Test("createDirectoryIfNeeded() creates a new directory")
    func testCreateDirectoryIfNeeded_createsNewDirectory() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let newDirPath = FileManager.Path.url(tempDir.appendingPathComponent("newDir"))
            #expect(try !FileManager.default.fileExists(atPath: newDirPath.url().path))
            
            // Act
            try newDirPath.createDirectoryIfNeeded()
            
            // Assert
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: try newDirPath.url().path, isDirectory: &isDirectory)
            #expect(exists)
            #expect(isDirectory.boolValue)
        }
    }
    
    /// `createDirectoryIfNeeded()`가 중간 경로를 포함하여 디렉토리를 생성하는지 검증합니다.
    /// - Intent: 여러 단계로 중첩된 경로에 대해 모든 중간 디렉토리를 자동으로 생성하는 기능을 확인합니다.
    /// - Given: 존재하지 않는 중첩된 디렉토리 경로.
    /// - When: `createDirectoryIfNeeded()`를 호출합니다.
    /// - Then: 최종 경로와 모든 중간 경로에 디렉토리가 생성되어야 합니다.
    @Test("createDirectoryIfNeeded() creates intermediate directories")
    func testCreateDirectoryIfNeeded_intermediateDirectories() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let nestedDirPath = FileManager.Path.url(tempDir.appendingPathComponent("intermediate/nested/dir"))
            #expect(try !FileManager.default.fileExists(atPath: nestedDirPath.url().path))
            
            // Act
            try nestedDirPath.createDirectoryIfNeeded()
            
            // Assert
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: try nestedDirPath.url().path, isDirectory: &isDirectory)
            #expect(exists)
            #expect(isDirectory.boolValue)
        }
    }
    
    /// `createDirectoryIfNeeded()`가 이미 디렉토리로 존재하는 경로에 대해 오류를 발생시키지 않는지 검증합니다.
    /// - Intent: 멱등성(idempotency)을 확인합니다. 이미 원하는 상태일 때 추가 작업을 수행하지 않고 조용히 성공해야 합니다.
    /// - Given: 이미 생성되어 있는 디렉토리 경로.
    /// - When: `createDirectoryIfNeeded()`를 다시 호출합니다.
    /// - Then: 아무런 오류도 발생하지 않아야 합니다.
    @Test("createDirectoryIfNeeded() does not throw when directory already exists")
    func testCreateDirectoryIfNeeded_alreadyExistsAsDirectory() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let existingDirPath = FileManager.Path.url(tempDir.appendingPathComponent("existingDir"))
            try FileManager.default.createDirectory(at: try existingDirPath.url(), withIntermediateDirectories: false)
            #expect(try existingDirPath.isDirectory())
            
            // Act & Assert: createDirectoryIfNeeded()가 오류를 발생시키지 않는지 확인합니다.
            try existingDirPath.createDirectoryIfNeeded()
        }
    }
    
    /// `createDirectoryIfNeeded()`가 파일이 이미 존재하는 경로에 대해 오류를 발생시키는지 검증합니다.
    /// - Intent: 디렉토리를 생성하려는 경로에 파일이 있는 경우, 덮어쓰지 않고 명확한 오류를 발생시키는지 확인합니다.
    /// - Given: 파일이 미리 생성되어 있는 경로.
    /// - When: `createDirectoryIfNeeded()`를 호출합니다.
    /// - Then: `SwiftVaultError.couldNotCreateDirectory` 오류가 발생해야 합니다.
    @Test("createDirectoryIfNeeded() throws error when path exists as a file")
    func testCreateDirectoryIfNeeded_pathExistsAsFile_throwsError() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let filePath = FileManager.Path.url(tempDir.appendingPathComponent("aFile.txt"))
            try "hello".data(using: .utf8)!.write(to: try filePath.url())
            #expect(try FileManager.default.fileExists(atPath: filePath.url().path))
            
            // Act & Assert
            #expect(throws: SwiftVaultError.self) {
                try filePath.createDirectoryIfNeeded()
            }
        }
    }
    
    // MARK: - File Operations (Save, Read, Delete)
    
    /// 데이터 저장 및 읽기가 정상적으로 동작하는지 검증합니다.
    /// - Intent: 파일에 데이터를 쓰고 다시 읽어와 원본과 동일한지 확인합니다.
    /// - Given: 저장할 데이터와 파일 경로.
    /// - When: `save(data:)`를 호출한 후 `read()`를 호출합니다.
    /// - Then: 저장된 파일이 존재해야 하며, 읽어온 데이터는 원본과 일치해야 합니다.
    @Test("Saving and reading data succeeds")
    func testSaveAndReadData() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let filePath = FileManager.Path.url(tempDir.appendingPathComponent("data.bin"))
            let originalData = UUID().uuidString.data(using: .utf8)!
            
            // Act (Save)
            try filePath.save(data: originalData)
            
            // Assert (Save)
            #expect(try FileManager.default.fileExists(at: filePath.url()))
            
            // Act (Read)
            let readData = try filePath.read()
            
            // Assert (Read)
            #expect(readData == originalData)
        }
    }
    
    /// `save(data:)`가 중간 디렉토리를 자동으로 생성하는지 검증합니다.
    /// - Intent: 파일 저장 시 상위 경로가 존재하지 않으면 자동으로 생성하여 저장을 성공시키는 기능을 확인합니다.
    /// - Given: 존재하지 않는 중첩된 경로 안의 파일 경로.
    /// - When: `save(data:)`를 호출합니다.
    /// - Then: 파일과 모든 중간 디렉토리가 생성되어야 합니다.
    @Test("save(data:) creates intermediate directories")
    func testSaveData_createsIntermediateDirectories() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let nestedFilePath = FileManager.Path.url(tempDir.appendingPathComponent("a/b/c/file.txt"))
            let data = "content".data(using: .utf8)!
            #expect(try !FileManager.default.fileExists(atPath: nestedFilePath.parentDirectoryURL().path))
            
            // Act
            try nestedFilePath.save(data: data)
            
            // Assert
            #expect(try FileManager.default.fileExists(atPath: nestedFilePath.url().path))
            #expect(try FileManager.default.fileExists(atPath: nestedFilePath.parentDirectoryURL().path))
        }
    }
    
    /// 존재하지 않는 파일에 `read()`를 시도할 때 오류가 발생하는지 검증합니다.
    /// - Intent: 없는 파일을 읽으려 할 때 `fileDoesNotExist` 오류를 정확히 발생시키는지 확인합니다.
    /// - Given: 존재하지 않는 파일 경로.
    /// - When: `read()`를 호출합니다.
    /// - Then: `SwiftVaultError.fileDoesNotExist` 오류가 발생해야 합니다.
    @Test("read() from non-existent file throws error")
    func testRead_fileDoesNotExist_throwsError() throws {
        try withTemporaryDirectory { tempDir in
            let nonExistentPath = FileManager.Path.url(tempDir.appendingPathComponent("ghost.txt"))
            #expect(throws: SwiftVaultError.self) {
                _ = try nonExistentPath.read()
            }
        }
    }
    
    /// 파일과 디렉토리를 성공적으로 삭제하는지 검증합니다.
    /// - Intent: `delete()` 메서드가 파일과 디렉토리 모두에 대해 올바르게 동작하는지 확인합니다.
    /// - Given: 미리 생성된 파일과 디렉토리.
    /// - When: 각 경로에 대해 `delete()`를 호출합니다.
    /// - Then: 해당 파일과 디렉토리가 파일 시스템에서 사라져야 합니다.
    @Test("delete() successfully removes file and directory")
    func testDeleteFileAndDirectory() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange (File)
            let filePath = FileManager.Path.url(tempDir.appendingPathComponent("toDelete.txt"))
            try "delete me".data(using: .utf8)!.write(to: try filePath.url())
            #expect(try FileManager.default.fileExists(atPath: filePath.url().path))
            
            // Arrange (Directory)
            let dirPath = FileManager.Path.url(tempDir.appendingPathComponent("dirToDelete"))
            try FileManager.default.createDirectory(at: try dirPath.url(), withIntermediateDirectories: false)
            #expect(try FileManager.default.fileExists(atPath: dirPath.url().path))
            
            // Act
            try filePath.delete()
            try dirPath.delete()
            
            // Assert
            #expect(try !FileManager.default.fileExists(atPath: filePath.url().path))
            #expect(try !FileManager.default.fileExists(atPath: dirPath.url().path))
        }
    }
    
    // MARK: - Unsupported Operations on Web URLs
    
    /// 웹 URL에 `save(data:)`를 시도할 때 오류가 발생하는지 검증합니다.
    /// - Intent: 파일 시스템 작업이 아닌 URL에 대해 `unsupportedOperation` 오류를 발생시켜 오용을 방지하는지 확인합니다.
    /// - Given: `https` 스킴을 가진 웹 URL.
    /// - When: `save(data:)`를 호출합니다.
    /// - Then: `SwiftVaultError.unsupportedOperation` 오류가 발생해야 합니다.
    @Test("save(data:) to non-file URL throws error")
    func testSaveToWebURLThrowsError() throws {
        let webURL = try #require(URL(string: "https://example.com/file.txt"))
        let webPath = FileManager.Path.url(webURL)
        let data = Data()
        
        #expect(throws: SwiftVaultError.self) {
            try webPath.save(data: data)
        }
    }
    
    // MARK: - Other Utilities
    
    /// `isDirectory()`가 파일, 디렉토리, 존재하지 않는 경로에 대해 정확히 동작하는지 검증합니다.
    /// - Intent: 경로가 가리키는 대상의 종류를 정확히 판별하는지 확인합니다.
    /// - Given: 파일, 디렉토리, 존재하지 않는 경로.
    /// - When: 각 경로에 대해 `isDirectory()`를 호출합니다.
    /// - Then: 디렉토리에 대해서만 `true`를 반환해야 합니다.
    @Test("isDirectory returns correct value for file, directory, and non-existent path")
    func testIsDirectory() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let dirPath = FileManager.Path.url(tempDir)
            let filePath = FileManager.Path.url(tempDir.appendingPathComponent("file.txt"))
            let nonExistentPath = FileManager.Path.url(tempDir.appendingPathComponent("ghost"))
            try "data".data(using: .utf8)!.write(to: try filePath.url())
            
            // Act & Assert
            #expect(try dirPath.isDirectory() == true)
            #expect(try filePath.isDirectory() == false)
            #expect(try nonExistentPath.isDirectory() == false)
        }
    }
    
    /// `fileName()`이 경로의 마지막 구성요소를 정확히 반환하는지 검증합니다.
    /// - Intent: URL에서 파일명 또는 마지막 디렉토리명을 올바르게 추출하는지 확인합니다.
    /// - Given: 여러 형태의 파일 및 디렉토리 경로.
    /// - When: `fileName()`를 호출합니다.
    /// - Then: 예상된 마지막 구성요소 문자열을 반환해야 합니다.
    @Test("fileName() returns the last path component")
    func testFileName() throws {
        try withTemporaryDirectory { tempDir in
            // Arrange
            let path1 = FileManager.Path.url(tempDir.appendingPathComponent("folder/file.name.txt"))
            let path2 = FileManager.Path.url(tempDir.appendingPathComponent("directory/"))
            let path3 = FileManager.Path.url(tempDir.appendingPathComponent("rootfile"))
            
            // Act
            let fileName1 = try path1.fileName()
            let fileName2 = try path2.fileName()
            let fileName3 = try path3.fileName()
            
            // Assert
            #expect(fileName1 == "file.name.txt")
            #expect(fileName2 == "directory")
            #expect(fileName3 == "rootfile")
        }
    }
    
    // MARK: - App-level Directory Operations
    
    /// `clearApplicationDirectories()`가 Documents, Caches, Application Support 디렉토리의 내용을 모두 삭제하는지 검증합니다.
    /// - Intent: 앱의 주요 저장소들을 초기화하는 기능이 올바르게 동작하는지 확인합니다.
    /// - Given: Documents, Caches, Application Support 디렉토리에 임시 파일들이 생성된 상태.
    /// - When: `clearApplicationDirectories()`를 호출합니다.
    /// - Then: 생성했던 임시 파일들이 모두 존재하지 않아야 합니다.
    @Test("clearApplicationDirectories() removes contents of all specified directories")
    func testClearApplicationDirectories() throws {
        // Arrange: 각 디렉토리에 더미 파일 생성
        let fm = FileManager.default
        let docPath = FileManager.Path.document("dummy_for_clear_test.txt")
        let cachePath = FileManager.Path.cache("dummy_for_clear_test.txt")
        let supportPath = FileManager.Path.applicationSupport("dummy_for_clear_test.txt")
        
        let testData = "test".data(using: .utf8)!
        try docPath.save(data: testData)
        try cachePath.save(data: testData)
        try supportPath.save(data: testData)
        
        #expect(try fm.fileExists(at: docPath.url()))
        #expect(try fm.fileExists(at: cachePath.url()))
        #expect(try fm.fileExists(at: supportPath.url()))
        
        // Act
        try fm.clearApplicationDirectories()
        
        // Assert
        #expect(try !fm.fileExists(at: docPath.url()))
        #expect(try !fm.fileExists(at: cachePath.url()))
        #expect(try !fm.fileExists(at: supportPath.url()))
    }
    
    // MARK: - Additional Unsupported Operations Tests
    
    /// 웹 URL에 `read()`를 시도할 때 오류가 발생하는지 검증합니다.
    @Test("read() from non-file URL throws error")
    func testReadFromWebURLThrowsError() throws {
        let webURL = try #require(URL(string: "https://example.com"))
        let webPath = FileManager.Path.url(webURL)
        #expect(throws: SwiftVaultError.self) {
            _ = try webPath.read()
        }
    }
    
    /// 웹 URL에 `delete()`를 시도할 때 오류가 발생하는지 검증합니다.
    @Test("delete() on non-file URL throws error")
    func testDeleteWebURLThrowsError() throws {
        let webURL = try #require(URL(string: "https://example.com"))
        let webPath = FileManager.Path.url(webURL)
        #expect(throws: SwiftVaultError.self) {
            try webPath.delete()
        }
    }
    
    // MARK: - Additional Edge Case Tests
    
    /// 존재하지 않는 파일에 `delete()`를 시도할 때 오류가 발생하는지 검증합니다.
    @Test("delete() on non-existent file throws error")
    func testDeleteNonExistentFileThrowsError() throws {
        try withTemporaryDirectory { tempDir in
            let nonExistentPath = FileManager.Path.url(tempDir.appendingPathComponent("ghost.txt"))
            #expect(throws: SwiftVaultError.self) {
                try nonExistentPath.delete()
            }
        }
    }
}
