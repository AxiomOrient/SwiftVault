# Testing Guide

This guide covers comprehensive testing strategies for SwiftVault-based applications, including unit testing, integration testing, and UI testing.

## Overview

Testing SwiftVault applications involves several layers:

1. **Unit Tests**: Test individual storage definitions and data models
2. **Integration Tests**: Test storage operations with real backends
3. **Migration Tests**: Verify data migration correctness
4. **UI Tests**: Test SwiftUI views with storage dependencies
5. **Performance Tests**: Measure storage operation performance

## Unit Testing

### Testing Data Models

Test your data models independently of storage:

```swift
import XCTest
@testable import YourApp

class UserDataModelTests: XCTestCase {
    
    func testUserProfileCreation() {
        let profile = UserProfile(
            name: "John Doe",
            email: "john@example.com",
            preferences: UserPreferences.default
        )
        
        XCTAssertEqual(profile.name, "John Doe")
        XCTAssertEqual(profile.email, "john@example.com")
        XCTAssertNotNil(profile.preferences)
    }
    
    func testUserProfileEquality() {
        let profile1 = UserProfile(name: "John", email: "john@example.com", preferences: .default)
        let profile2 = UserProfile(name: "John", email: "john@example.com", preferences: .default)
        let profile3 = UserProfile(name: "Jane", email: "jane@example.com", preferences: .default)
        
        XCTAssertEqual(profile1, profile2)
        XCTAssertNotEqual(profile1, profile3)
    }
    
    func testUserProfileCodable() throws {
        let originalProfile = UserProfile(
            name: "Test User",
            email: "test@example.com",
            preferences: UserPreferences(theme: "dark", notifications: true)
        )
        
        // Test encoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalProfile)
        
        // Test decoding
        let decoder = JSONDecoder()
        let decodedProfile = try decoder.decode(UserProfile.self, from: data)
        
        XCTAssertEqual(originalProfile, decodedProfile)
    }
}
```

### Testing Storage Definitions

Test your VaultStorable implementations:

```swift
class StorageDefinitionTests: XCTestCase {
    
    func testUserProfileStorageDefaults() {
        let defaultValue = UserProfileStorage.defaultValue
        
        XCTAssertEqual(defaultValue.name, "Guest")
        XCTAssertEqual(defaultValue.email, "")
        XCTAssertEqual(defaultValue.preferences.theme, "light")
    }
    
    func testStorageTypeConfiguration() {
        XCTAssertEqual(UserProfileStorage.storageType, .userDefaults())
        XCTAssertEqual(AuthTokenStorage.storageType, .keychain(keyPrefix: "auth_"))
        XCTAssertEqual(DocumentsStorage.storageType, .fileSystem())
    }
    
    func testCustomEncoderDecoder() throws {
        let encoder = UserProfileStorage.encoder
        let decoder = UserProfileStorage.decoder
        
        let testProfile = UserProfile.test
        let encoded = try encoder.encode(testProfile)
        let decoded = try decoder.decode(UserProfile.self, from: encoded)
        
        XCTAssertEqual(testProfile, decoded)
    }
}
```

## Mock Services for Testing

### Creating Mock SwiftVaultService

Create a mock service for isolated testing:

```swift
class MockSwiftVaultService: SwiftVaultService {
    private var storage: [String: Data] = [:]
    private var shouldFail = false
    private let changeSubject = PassthroughSubject<(key: String?, transactionID: UUID?), Never>()
    
    // MARK: - Test Configuration
    
    func setShouldFail(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }
    
    func simulateExternalChange(key: String?, transactionID: UUID? = nil) {
        changeSubject.send((key: key, transactionID: transactionID))
    }
    
    func clearStorage() {
        storage.removeAll()
    }
    
    // MARK: - SwiftVaultService Implementation
    
    func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
        if shouldFail {
            throw SwiftVaultError.writeFailed(key: key)
        }
        storage[key] = data
        changeSubject.send((key: key, transactionID: transactionID))
    }
    
    func loadData(forKey key: String) async throws -> Data? {
        if shouldFail {
            throw SwiftVaultError.readFailed(key: key)
        }
        return storage[key]
    }
    
    func remove(forKey key: String) async throws {
        if shouldFail {
            throw SwiftVaultError.deleteFailed(key: key)
        }
        storage.removeValue(forKey: key)
        changeSubject.send((key: key, transactionID: nil))
    }
    
    func exists(forKey key: String) async -> Bool {
        return storage[key] != nil
    }
    
    func clearAll() async throws {
        if shouldFail {
            throw SwiftVaultError.clearAllFailed()
        }
        storage.removeAll()
        changeSubject.send((key: nil, transactionID: nil))
    }
    
    nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> {
        AsyncStream { continuation in
            let cancellable = changeSubject.sink { change in
                continuation.yield(change)
            }
            
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}
```

### Using Mock Storage in Tests

```swift
class VaultStoredTests: XCTestCase {
    private var mockService: MockSwiftVaultService!
    
    override func setUp() {
        super.setUp()
        mockService = MockSwiftVaultService()
    }
    
    override func tearDown() {
        mockService = nil
        super.tearDown()
    }
    
    func testDataPersistence() async throws {
        // Create test data
        let testProfile = UserProfile(
            name: "Test User",
            email: "test@example.com",
            preferences: UserPreferences.default
        )
        
        // Save data
        let encoder = JSONEncoder()
        let data = try encoder.encode(testProfile)
        try await mockService.saveData(data, forKey: "test_profile", transactionID: UUID())
        
        // Load data
        let loadedData = try await mockService.loadData(forKey: "test_profile")
        XCTAssertNotNil(loadedData)
        
        let decoder = JSONDecoder()
        let loadedProfile = try decoder.decode(UserProfile.self, from: loadedData!)
        
        XCTAssertEqual(testProfile, loadedProfile)
    }
    
    func testDataRemoval() async throws {
        // Save test data
        let testData = "test data".data(using: .utf8)!
        try await mockService.saveData(testData, forKey: "test_key", transactionID: UUID())
        
        // Verify it exists
        XCTAssertTrue(await mockService.exists(forKey: "test_key"))
        
        // Remove it
        try await mockService.remove(forKey: "test_key")
        
        // Verify it's gone
        XCTAssertFalse(await mockService.exists(forKey: "test_key"))
        let loadedData = try await mockService.loadData(forKey: "test_key")
        XCTAssertNil(loadedData)
    }
    
    func testErrorHandling() async {
        mockService.setShouldFail(true)
        
        do {
            try await mockService.saveData(Data(), forKey: "test", transactionID: UUID())
            XCTFail("Expected error to be thrown")
        } catch SwiftVaultError.writeFailed(let key, _) {
            XCTAssertEqual(key, "test")
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
```

## Integration Testing

### Testing with Real Storage Backends

Test your storage with actual SwiftVault services:

```swift
class IntegrationTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileSystemService: SwiftVaultService!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create file system service
        fileSystemService = try SwiftVault.fileSystem(
            location: .custom(directory: .url(tempDirectory))
        )
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        fileSystemService = nil
        
        try await super.tearDown()
    }
    
    func testFileSystemPersistence() async throws {
        let testData = "Hello, SwiftVault!".data(using: .utf8)!
        let transactionID = UUID()
        
        // Save data
        try await fileSystemService.saveData(testData, forKey: "greeting", transactionID: transactionID)
        
        // Verify it exists
        XCTAssertTrue(await fileSystemService.exists(forKey: "greeting"))
        
        // Load data
        let loadedData = try await fileSystemService.loadData(forKey: "greeting")
        XCTAssertEqual(testData, loadedData)
        
        // Verify file was created
        let expectedFilePath = tempDirectory.appendingPathComponent("greeting")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedFilePath.path))
    }
    
    func testUserDefaultsPersistence() async throws {
        // Use a custom suite for testing
        let testSuite = UserDefaults(suiteName: "com.test.swiftvault")!
        let service = SwiftVault.userDefaults(suiteName: "com.test.swiftvault")
        
        defer {
            // Clean up test suite
            testSuite.removePersistentDomain(forName: "com.test.swiftvault")
        }
        
        let testData = "UserDefaults test".data(using: .utf8)!
        try await service.saveData(testData, forKey: "test_key", transactionID: UUID())
        
        let loadedData = try await service.loadData(forKey: "test_key")
        XCTAssertEqual(testData, loadedData)
    }
}
```

### Testing External Change Detection

```swift
class ExternalChangeTests: XCTestCase {
    
    func testExternalChangeNotification() async throws {
        let service = try SwiftVault.fileSystem()
        let expectation = XCTestExpectation(description: "External change detected")
        
        // Start monitoring changes
        let monitoringTask = Task {
            for await (key, transactionID) in service.externalChanges {
                if key == "test_key" {
                    expectation.fulfill()
                    break
                }
            }
        }
        
        // Make a change
        try await service.saveData("test".data(using: .utf8)!, forKey: "test_key", transactionID: UUID())
        
        await fulfillment(of: [expectation], timeout: 5.0)
        monitoringTask.cancel()
    }
}
```

## Migration Testing

### Testing Data Migration

```swift
class MigrationTests: XCTestCase {
    
    func testUserProfileMigration() async throws {
        // Create old version data
        let oldProfile = UserProfileV1(name: "John Doe", email: "john@example.com")
        let oldData = try JSONEncoder().encode(oldProfile)
        
        // Create migrator
        let builder = DataMigrator<UserProfile>.Builder(targetType: UserProfile.self)
        UserProfileStorage.configure(builder: builder)
        let migrator = builder.build()
        
        // Perform migration
        let (migratedData, wasMigrated) = try await migrator.migrate(data: oldData)
        XCTAssertTrue(wasMigrated)
        
        // Verify migrated data
        let newProfile = try JSONDecoder().decode(UserProfile.self, from: migratedData)
        XCTAssertEqual(newProfile.name, "John Doe")
        XCTAssertEqual(newProfile.email, "john@example.com")
        XCTAssertNotNil(newProfile.preferences) // Added in migration
    }
    
    func testMigrationChain() async throws {
        // Test complete migration chain V1 -> V2 -> V3
        let v1Data = UserDataV1(name: "Test")
        let v1Encoded = try JSONEncoder().encode(v1Data)
        
        let builder = DataMigrator<UserDataV3>.Builder(targetType: UserDataV3.self)
        builder
            .register(from: UserDataV1.self, to: UserDataV2.self) { v1 in
                UserDataV2(name: v1.name, email: "")
            }
            .register(from: UserDataV2.self, to: UserDataV3.self) { v2 in
                UserDataV3(name: v2.name, email: v2.email, preferences: [:])
            }
        
        let migrator = builder.build()
        let (migratedData, wasMigrated) = try await migrator.migrate(data: v1Encoded)
        
        XCTAssertTrue(wasMigrated)
        let v3Data = try JSONDecoder().decode(UserDataV3.self, from: migratedData)
        XCTAssertEqual(v3Data.name, "Test")
        XCTAssertEqual(v3Data.email, "")
        XCTAssertTrue(v3Data.preferences.isEmpty)
    }
    
    func testMigrationFailure() async throws {
        // Test migration with invalid data
        let invalidData = "invalid json".data(using: .utf8)!
        
        let builder = DataMigrator<UserProfile>.Builder(targetType: UserProfile.self)
        let migrator = builder.build()
        
        do {
            _ = try await migrator.migrate(data: invalidData)
            XCTFail("Expected migration to fail")
        } catch {
            // Expected failure
            XCTAssertTrue(error is MigrationError)
        }
    }
}
```

## SwiftUI Testing

### Testing Views with VaultStored

```swift
import SwiftUI
import ViewInspector
@testable import YourApp

class SwiftUIStorageTests: XCTestCase {
    
    func testUserProfileView() throws {
        // This test requires a testing framework like ViewInspector
        // or you can test the underlying data logic
        
        let mockStorage = MockUserProfileStorage()
        mockStorage.setValue(UserProfile(name: "Test User", email: "test@example.com", preferences: .default))
        
        // Test that the view displays the correct data
        // Implementation depends on your testing framework
    }
    
    func testStorageBinding() {
        // Test that changes to storage update the UI
        let mockStorage = MockUserProfileStorage()
        
        // Initial state
        XCTAssertEqual(mockStorage.value.name, "Guest")
        
        // Simulate user input
        mockStorage.setValue(UserProfile(name: "Updated Name", email: "", preferences: .default))
        
        // Verify change
        XCTAssertEqual(mockStorage.value.name, "Updated Name")
    }
}

// Mock storage for testing
class MockUserProfileStorage: ObservableObject {
    @Published var value = UserProfile(name: "Guest", email: "", preferences: .default)
    
    func setValue(_ newValue: UserProfile) {
        value = newValue
    }
}
```

### Testing Property Wrappers

```swift
class PropertyWrapperTests: XCTestCase {
    
    func testUserDefaultWrapper() {
        let mockDefaults = MockUserDefaults()
        
        @UserDefault("test_key", store: mockDefaults)
        var testValue: String = "default"
        
        // Test initial value
        XCTAssertEqual(testValue, "default")
        
        // Test setting value
        testValue = "updated"
        XCTAssertEqual(testValue, "updated")
        XCTAssertEqual(mockDefaults.object(forKey: "test_key") as? String, "updated")
        
        // Test reset
        $testValue.reset()
        XCTAssertEqual(testValue, "default")
        XCTAssertNil(mockDefaults.object(forKey: "test_key"))
    }
    
    func testCodableUserDefaultWrapper() throws {
        let mockDefaults = MockUserDefaults()
        
        @CodableUserDefault("profile_key", store: mockDefaults)
        var profile: UserProfile = UserProfile.guest
        
        // Test initial value
        XCTAssertEqual(profile, UserProfile.guest)
        
        // Test setting complex value
        let newProfile = UserProfile(name: "Test", email: "test@example.com", preferences: .default)
        profile = newProfile
        XCTAssertEqual(profile, newProfile)
        
        // Verify it was encoded and stored
        let storedData = mockDefaults.data(forKey: "profile_key")
        XCTAssertNotNil(storedData)
        
        let decodedProfile = try JSONDecoder().decode(UserProfile.self, from: storedData!)
        XCTAssertEqual(decodedProfile, newProfile)
    }
}

// Mock UserDefaults for testing
class MockUserDefaults: UserDefaultsProvider {
    private var storage: [String: Any] = [:]
    
    func object(forKey key: String) -> Any? {
        return storage[key]
    }
    
    func data(forKey key: String) -> Data? {
        return storage[key] as? Data
    }
    
    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }
    
    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
    
    func bool(forKey key: String) -> Bool {
        return storage[key] as? Bool ?? false
    }
    
    func removePersistentDomain(forName domainName: String) {
        storage.removeAll()
    }
}
```

## Performance Testing

### Measuring Storage Performance

```swift
class PerformanceTests: XCTestCase {
    
    func testUserDefaultsPerformance() {
        let service = SwiftVault.userDefaults()
        let testData = "Performance test data".data(using: .utf8)!
        
        measure {
            let group = DispatchGroup()
            
            for i in 0..<100 {
                group.enter()
                Task {
                    try await service.saveData(testData, forKey: "perf_test_\(i)", transactionID: UUID())
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
    
    func testFileSystemPerformance() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let service = try SwiftVault.fileSystem(location: .custom(directory: .url(tempDir)))
        let testData = Data(repeating: 0, count: 1024 * 1024) // 1MB of data
        
        measure {
            let group = DispatchGroup()
            
            for i in 0..<10 {
                group.enter()
                Task {
                    try await service.saveData(testData, forKey: "large_file_\(i)", transactionID: UUID())
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
    
    func testMigrationPerformance() throws {
        // Create large dataset for migration testing
        let largeDataset = (0..<1000).map { i in
            UserDataV1(name: "User \(i)", email: "user\(i)@example.com")
        }
        
        let encodedData = try JSONEncoder().encode(largeDataset)
        
        let builder = DataMigrator<[UserData]>.Builder(targetType: [UserData].self)
        builder.register(from: [UserDataV1].self, to: [UserData].self) { v1Array in
            v1Array.map { v1 in
                UserData(name: v1.name, email: v1.email, preferences: .default)
            }
        }
        let migrator = builder.build()
        
        measure {
            Task {
                _ = try await migrator.migrate(data: encodedData)
            }
        }
    }
}
```

## Test Organization

### Test Structure

Organize your tests into logical groups:

```
Tests/
├── UnitTests/
│   ├── DataModelTests.swift
│   ├── StorageDefinitionTests.swift
│   └── PropertyWrapperTests.swift
├── IntegrationTests/
│   ├── FileSystemIntegrationTests.swift
│   ├── UserDefaultsIntegrationTests.swift
│   └── KeychainIntegrationTests.swift
├── MigrationTests/
│   ├── UserDataMigrationTests.swift
│   └── MigrationChainTests.swift
├── UITests/
│   ├── SwiftUIStorageTests.swift
│   └── ViewBindingTests.swift
├── PerformanceTests/
│   └── StoragePerformanceTests.swift
└── Mocks/
    ├── MockSwiftVaultService.swift
    ├── MockUserDefaults.swift
    └── TestDataFactory.swift
```

### Test Data Factory

Create a factory for consistent test data:

```swift
enum TestDataFactory {
    static func createUserProfile(
        name: String = "Test User",
        email: String = "test@example.com",
        preferences: UserPreferences = .default
    ) -> UserProfile {
        return UserProfile(name: name, email: email, preferences: preferences)
    }
    
    static func createUserProfiles(count: Int) -> [UserProfile] {
        return (0..<count).map { i in
            createUserProfile(
                name: "User \(i)",
                email: "user\(i)@example.com"
            )
        }
    }
    
    static func createLargeTestData(sizeInMB: Int) -> Data {
        let bytesPerMB = 1024 * 1024
        return Data(repeating: 0, count: sizeInMB * bytesPerMB)
    }
}
```

## Continuous Integration

### GitHub Actions Example

```yaml
name: SwiftVault Tests

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Select Xcode
      run: sudo xcode-select -switch /Applications/Xcode_15.0.app/Contents/Developer
    
    - name: Run Unit Tests
      run: |
        xcodebuild test \
          -scheme SwiftVault \
          -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
          -testPlan UnitTests
    
    - name: Run Integration Tests
      run: |
        xcodebuild test \
          -scheme SwiftVault \
          -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
          -testPlan IntegrationTests
    
    - name: Run Performance Tests
      run: |
        xcodebuild test \
          -scheme SwiftVault \
          -destination 'platform=iOS Simulator,name=iPhone 15,OS=17.0' \
          -testPlan PerformanceTests
```

## Best Testing Practices

### 1. Test Isolation

Ensure tests don't affect each other:

```swift
class IsolatedTests: XCTestCase {
    private var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create isolated environment for each test
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up after each test
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        
        try await super.tearDown()
    }
}
```

### 2. Test All Error Paths

```swift
func testAllErrorScenarios() async {
    let mockService = MockSwiftVaultService()
    
    // Test write failure
    mockService.setShouldFail(true)
    do {
        try await mockService.saveData(Data(), forKey: "test", transactionID: UUID())
        XCTFail("Expected write to fail")
    } catch SwiftVaultError.writeFailed {
        // Expected
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
    
    // Test read failure
    do {
        _ = try await mockService.loadData(forKey: "test")
        XCTFail("Expected read to fail")
    } catch SwiftVaultError.readFailed {
        // Expected
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}
```

### 3. Test Edge Cases

```swift
func testEdgeCases() async throws {
    let service = MockSwiftVaultService()
    
    // Test empty data
    try await service.saveData(Data(), forKey: "empty", transactionID: UUID())
    let emptyData = try await service.loadData(forKey: "empty")
    XCTAssertEqual(emptyData, Data())
    
    // Test large data
    let largeData = Data(repeating: 0xFF, count: 10 * 1024 * 1024) // 10MB
    try await service.saveData(largeData, forKey: "large", transactionID: UUID())
    let loadedLargeData = try await service.loadData(forKey: "large")
    XCTAssertEqual(loadedLargeData, largeData)
    
    // Test special characters in keys
    let specialKey = "key with spaces & symbols!@#$%"
    try await service.saveData("test".data(using: .utf8)!, forKey: specialKey, transactionID: UUID())
    XCTAssertTrue(await service.exists(forKey: specialKey))
}
```

## Summary

Comprehensive testing of SwiftVault applications involves:

- ✅ **Unit Tests**: Test data models and storage definitions in isolation
- ✅ **Mock Services**: Use mock implementations for fast, reliable tests
- ✅ **Integration Tests**: Test with real storage backends
- ✅ **Migration Tests**: Verify data migration correctness
- ✅ **UI Tests**: Test SwiftUI integration and bindings
- ✅ **Performance Tests**: Measure and monitor storage performance
- ✅ **Error Testing**: Test all failure scenarios
- ✅ **Edge Cases**: Test boundary conditions and special cases

Good testing practices ensure your SwiftVault-based applications are reliable, performant, and maintainable in production.