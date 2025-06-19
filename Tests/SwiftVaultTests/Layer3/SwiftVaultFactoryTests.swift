import Testing
@testable import SwiftVault
import Foundation

/// `SwiftVault` 팩토리 메서드의 동작을 검증하는 테스트 스위트입니다.
@Suite("SwiftVault Factory Tests")
@MainActor
struct SwiftVaultFactoryTests {

    /// **Intent:** `SwiftVault.userDefaults()` 팩토리가 `SwiftVaultUserDefaultsService`의 올바른 인스턴스를 반환하는지 검증합니다.
    @Test("userDefaults factory creates correct service type")
    func testUserDefaultsFactory() {
        // Arrange & Act
        let defaultService = SwiftVault.userDefaults()
        let suiteService = SwiftVault.userDefaults(suiteName: "testSuite")

        // Assert
        #expect(defaultService is SwiftVaultUserDefaultsService, "Default factory should create a UserDefaults service.")
        #expect(suiteService is SwiftVaultUserDefaultsService, "Factory with suiteName should create a UserDefaults service.")
    }

    /// **Intent:** `SwiftVault.fileSystem()` 팩토리가 `.default` 위치에 대해 오류 없이 서비스를 생성하는지 검증합니다.
    @Test("fileSystem factory creates service with default location")
    func testFileSystemFactoryDefaultLocation() throws {
        // Arrange & Act
        let service = try SwiftVault.fileSystem(location: .default)
        
        // Assert
        #expect(service is SwiftVaultFileSystemService, "Service should be a FileSystem service.")
    }
    
    /// **Intent:** `SwiftVault.fileSystem()` 팩토리가 `.custom` 위치에 대해 오류 없이 서비스를 생성하는지 검증합니다.
    @Test("fileSystem factory creates service with custom location")
    func testFileSystemFactoryCustomLocation() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Act
        let service = try SwiftVault.fileSystem(location: .custom(directory: .url(tempDir)))

        // Assert
        #expect(service is SwiftVaultFileSystemService, "Service should be a FileSystem service.")
        #expect(FileManager.default.fileExists(atPath: tempDir.path), "Custom directory should be created by the service.")
    }
}
