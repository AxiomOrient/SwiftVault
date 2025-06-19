import Testing
@testable import SwiftVault
import Foundation

/// `DataMigrator`의 데이터 마이그레이션 로직을 검증하는 테스트 스위트입니다.
@Suite("DataMigrator Tests")
@MainActor
struct DataMigratorTests {

    // MARK: - Models for Migration Test
    
    // 테스트에 사용될 모든 모델은 Equatable을 준수해야 합니다.
    private struct V1: Codable, Sendable, Equatable { let name: String }
    private struct V2: Codable, Sendable, Equatable { let firstName: String; let lastName: String }
    private struct V3: Codable, Sendable, Equatable { let fullName: String }

    // MARK: - Test Cases

    /// **Intent:** 마이그레이션이 필요 없는 최신 버전 데이터를 올바르게 처리하는지 검증합니다.
    @Test("Processes latest data version without migration")
    func testNoMigrationNeeded() async throws {
        // Arrange
        let migrator = DataMigrator.Builder(targetType: V3.self).build()
        let latestData = try JSONEncoder().encode(V3(fullName: "Gemini AI"))
        
        // Act
        let result = try await migrator.migrate(data: latestData)
        
        // Assert
        #expect(result.wasMigrated == false, "wasMigrated flag should be false when no migration is needed.")
        
        let decodedModel = try JSONDecoder().decode(V3.self, from: result.data)
        #expect(decodedModel.fullName == "Gemini AI")
    }

    /// **Intent:** 단일 단계 마이그레이션(V2 -> V3)이 성공하는지 검증합니다.
    @Test("Performs single-step migration successfully")
    func testSingleStepMigration() async throws {
        // Arrange
        let migrator = DataMigrator.Builder(targetType: V3.self)
            .register(from: V2.self, to: V3.self) { v2 in
                V3(fullName: "\(v2.firstName) \(v2.lastName)")
            }
            .build()
        
        let v2Data = try JSONEncoder().encode(V2(firstName: "Gemini", lastName: "AI"))

        // Act
        let result = try await migrator.migrate(data: v2Data)

        // Assert
        #expect(result.wasMigrated == true, "wasMigrated flag should be true after migration.")
        
        let migratedModel = try JSONDecoder().decode(V3.self, from: result.data)
        #expect(migratedModel.fullName == "Gemini AI", "The migrated V3 model should have the correct data.")
    }
    
    /// **Intent:** 연쇄 마이그레이션(V1 -> V2 -> V3)이 성공적으로 수행되는지 검증합니다.
    @Test("Performs chained migration successfully")
    func testChainedMigration() async throws {
        // Arrange
        let migrator = DataMigrator.Builder(targetType: V3.self)
            .register(from: V1.self, to: V2.self) { v1 in
                V2(firstName: v1.name, lastName: "Model")
            }
            .register(from: V2.self, to: V3.self) { v2 in
                V3(fullName: "\(v2.firstName) \(v2.lastName)")
            }
            .build()
        
        let v1Data = try JSONEncoder().encode(V1(name: "Gemini"))
        
        // Act
        let result = try await migrator.migrate(data: v1Data)

        // Assert
        #expect(result.wasMigrated == true, "wasMigrated flag should be true after chained migration.")
        
        let migratedModel = try JSONDecoder().decode(V3.self, from: result.data)
        #expect(migratedModel.fullName == "Gemini Model")
    }

    /// **Intent:** 마이그레이션 경로가 중간에 끊겼을 때 오류가 발생하는지 검증합니다.
    @Test("Throws error on broken migration path")
    func testBrokenMigrationPath() async throws {
        // Arrange
        // V1 -> V2 경로를 고의로 등록하지 않음
        let migrator = DataMigrator.Builder(targetType: V3.self)
            .register(from: V2.self, to: V3.self) { v2 in
                V3(fullName: "\(v2.firstName) \(v2.lastName)")
            }
            .build()

        let v1Data = try JSONEncoder().encode(V1(name: "Gemini"))
        
        // Act & Assert
        // MigrationError가 LocalizedError를 준수하므로, 더 구체적인 오류를 확인할 수 있습니다.
        await #expect(throws: (any Error).self) {
            _ = try await migrator.migrate(data: v1Data)
        }
    }

    /// **Intent:** 어떤 버전으로도 디코딩할 수 없는 손상된 데이터 로드 시 오류가 발생하는지 검증합니다.
    @Test("Throws error on corrupted data")
    func testCorruptedData() async throws {
        // Arrange
        let migrator = DataMigrator.Builder(targetType: V3.self)
            .register(from: V1.self, to: V2.self) { v1 in V2(firstName: v1.name, lastName: "Model") }
            .register(from: V2.self, to: V3.self) { v2 in V3(fullName: "\(v2.firstName) \(v2.lastName)") }
            .build()

        let corruptedData = "invalid data".data(using: .utf8)!
        
        // Act & Assert
        await #expect(throws: (any Error).self) {
            _ = try await migrator.migrate(data: corruptedData)
        }
    }
}
