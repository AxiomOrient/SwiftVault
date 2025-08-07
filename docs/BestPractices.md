# Best Practices

This guide outlines recommended patterns and practices for using SwiftVault effectively in production applications.

## Architecture Patterns

### 1. Organize Storage Definitions

Group related storage definitions together and use consistent naming conventions.

```swift
// MARK: - User Data Storage
struct UserProfileStorage: VaultStorable {
    typealias Value = UserProfile
    static let key = "user_profile_v2"
    static let defaultValue = UserProfile.guest
    static let storageType = SwiftVaultStorageType.userDefaults()
}

struct UserPreferencesStorage: VaultStorable {
    typealias Value = UserPreferences
    static let key = "user_preferences_v1"
    static let defaultValue = UserPreferences.default
    static let storageType = SwiftVaultStorageType.userDefaults()
}

// MARK: - App Configuration Storage
struct AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings
    static let key = "app_settings_v3"
    static let defaultValue = AppSettings.default
    static let storageType = SwiftVaultStorageType.userDefaults()
}

// MARK: - Sensitive Data Storage
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let key = "auth_token"
    static let defaultValue: String? = nil
    static let storageType = SwiftVaultStorageType.keychain(keyPrefix: "auth_")
}
```

### 2. Use Dedicated Storage Modules

Create separate modules for different storage concerns:

```swift
// UserStorage.swift
enum UserStorage {
    struct Profile: VaultStorable {
        typealias Value = UserProfile
        static let defaultValue = UserProfile.guest
    }
    
    struct Preferences: VaultStorable {
        typealias Value = UserPreferences
        static let defaultValue = UserPreferences.default
    }
    
    struct RecentSearches: VaultStorable {
        typealias Value = [String]
        static let defaultValue: [String] = []
        static let storageType = SwiftVaultStorageType.fileSystem()
    }
}

// Usage
struct ProfileView: View {
    @VaultStored(UserStorage.Profile.self) var profile
    @VaultStored(UserStorage.Preferences.self) var preferences
    
    var body: some View {
        // Your UI
    }
}
```

### 3. Create Storage Protocols for Consistency

Define protocols to ensure consistent storage patterns:

```swift
protocol UserDataStorable: VaultStorable where Value: Codable & Equatable {
    static var version: Int { get }
}

extension UserDataStorable {
    static var key: String {
        return "\(String(describing: Self.self).lowercased())_v\(version)"
    }
    
    static var storageType: SwiftVaultStorageType {
        return .userDefaults()
    }
}

// Usage
struct UserProfileStorage: UserDataStorable {
    typealias Value = UserProfile
    static let version = 2
    static let defaultValue = UserProfile.guest
}
```

## Data Modeling

### 1. Design for Evolution

Structure your data models to support future changes:

```swift
// ✅ Good - Extensible structure
struct UserProfile: Codable, Equatable {
    let version: Int = 2
    let core: CoreProfile
    let preferences: UserPreferences
    let metadata: ProfileMetadata
    
    struct CoreProfile: Codable, Equatable {
        let id: UUID
        let name: String
        let email: String
        let createdAt: Date
    }
    
    struct UserPreferences: Codable, Equatable {
        let theme: Theme
        let notifications: NotificationSettings
        let privacy: PrivacySettings
    }
    
    struct ProfileMetadata: Codable, Equatable {
        let lastUpdated: Date
        let syncStatus: SyncStatus
    }
}

// ❌ Avoid - Flat structure that's hard to evolve
struct UserProfile: Codable, Equatable {
    let name: String
    let email: String
    let theme: String
    let notificationsEnabled: Bool
    let privacyLevel: Int
    // Adding new fields becomes messy
}
```

### 2. Use Meaningful Default Values

Provide sensible defaults that make your app functional out of the box:

```swift
// ✅ Good - Thoughtful defaults
struct AppSettings: Codable, Equatable {
    let theme: Theme = .system           // Respects user's system preference
    let language: String = Locale.current.languageCode ?? "en"
    let notifications: Bool = true       // Opt-in by default
    let dataUsage: DataUsageLevel = .standard
    let accessibility: AccessibilitySettings = .default
    
    static let `default` = AppSettings()
}

// ❌ Avoid - Empty or meaningless defaults
struct AppSettings: Codable, Equatable {
    let theme: String = ""
    let language: String = ""
    let notifications: Bool = false
    let dataUsage: Int = 0
}
```

### 3. Version Your Data Structures

Include version information for future migration support:

```swift
struct UserDataV3: Codable, Equatable {
    static let version = 3
    
    let schemaVersion: Int = Self.version
    let userData: UserData
    let migrationInfo: MigrationInfo?
    
    struct MigrationInfo: Codable, Equatable {
        let migratedFrom: Int
        let migratedAt: Date
        let migrationNotes: String?
    }
}
```

## Storage Type Selection

### 1. Choose Appropriate Storage Types

Match storage types to your data characteristics:

```swift
// User preferences - UserDefaults (fast, small, frequently accessed)
struct ThemeStorage: VaultStorable {
    typealias Value = Theme
    static let storageType = .userDefaults()
}

// Authentication tokens - Keychain (sensitive, secure)
struct AuthStorage: VaultStorable {
    typealias Value = AuthCredentials
    static let storageType = .keychain(keyPrefix: "auth_")
}

// Document cache - File System (large, infrequently accessed)
struct DocumentCacheStorage: VaultStorable {
    typealias Value = [String: CachedDocument]
    static let storageType = .fileSystem()
}

// Shared data between app and widget - UserDefaults with App Group
struct WidgetDataStorage: VaultStorable {
    typealias Value = WidgetData
    static let storageType = .userDefaults(suiteName: "group.com.example.widget")
}
```

### 2. Consider Data Size and Access Patterns

```swift
// ✅ Good - Small, frequently accessed data in UserDefaults
struct UserPreferencesStorage: VaultStorable {
    typealias Value = UserPreferences  // Small struct
    static let storageType = .userDefaults()
}

// ✅ Good - Large data in File System
struct ImageCacheStorage: VaultStorable {
    typealias Value = [String: Data]  // Potentially large
    static let storageType = .fileSystem()
}

// ❌ Avoid - Large data in UserDefaults
struct LargeDataStorage: VaultStorable {
    typealias Value = [LargeDocument]  // Could be MBs
    static let storageType = .userDefaults()  // Will be slow
}
```

## Performance Optimization

### 1. Batch Related Data

Group related data together to minimize storage operations:

```swift
// ✅ Good - Grouped related settings
struct AppConfiguration: Codable, Equatable {
    let ui: UISettings
    let network: NetworkSettings
    let cache: CacheSettings
    let analytics: AnalyticsSettings
}

struct AppConfigurationStorage: VaultStorable {
    typealias Value = AppConfiguration
    static let storageType = .userDefaults()
}

// ❌ Avoid - Separate storage for each setting
@PublishedUserDefault("theme") var theme: String = "light"
@PublishedUserDefault("language") var language: String = "en"
@PublishedUserDefault("notifications") var notifications: Bool = true
@PublishedUserDefault("cacheSize") var cacheSize: Int = 100
// Multiple UserDefaults operations
```

### 2. Use Appropriate Property Wrappers

Choose the right property wrapper for your use case:

```swift
// For simple, non-reactive data
@UserDefault("simpleFlag") var flag: Bool = false

// For reactive data in SwiftUI
@PublishedUserDefault("userName") var userName: String = "Guest"

// For complex data with migration support
@VaultStored(UserProfileStorage.self) var profile
```

### 3. Minimize External Change Monitoring

Only monitor external changes when necessary:

```swift
// ✅ Good - Monitor only when needed
class DataSyncManager {
    private let service: SwiftVaultService
    private var monitoringTask: Task<Void, Never>?
    
    func startMonitoring() {
        guard monitoringTask == nil else { return }
        
        monitoringTask = Task {
            for await (key, transactionID) in service.externalChanges {
                await handleExternalChange(key: key, transactionID: transactionID)
            }
        }
    }
    
    func stopMonitoring() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }
}

// ❌ Avoid - Always monitoring even when not needed
class AlwaysMonitoringManager {
    init() {
        // This runs forever, even when not needed
        Task {
            for await change in service.externalChanges {
                // Process change
            }
        }
    }
}
```

## Error Handling

### 1. Implement Graceful Degradation

Handle errors gracefully without breaking the user experience:

```swift
class ResilientDataManager {
    @VaultStored(UserDataStorage.self) var userData
    
    func saveUserData(_ data: UserData) {
        do {
            userData = data
        } catch {
            // Log error but don't crash
            logger.error("Failed to save user data: \(error)")
            
            // Show user-friendly message
            showErrorMessage("Unable to save changes. Please try again.")
            
            // Optionally queue for retry
            queueForRetry(data)
        }
    }
    
    private func showErrorMessage(_ message: String) {
        // Show non-intrusive error message
        NotificationCenter.default.post(
            name: .userFriendlyError,
            object: message
        )
    }
    
    private func queueForRetry(_ data: UserData) {
        // Implement retry logic
        Task {
            try await Task.sleep(for: .seconds(5))
            saveUserData(data)
        }
    }
}
```

### 2. Validate Data During Migration

Ensure data integrity during migration:

```swift
struct UserDataStorage: VaultStorable {
    typealias Value = UserData
    static let defaultValue = UserData.safe
    
    static func configure(builder: DataMigrator<UserData>.Builder) {
        builder.register(from: UserDataV1.self, to: UserData.self) { v1 in
            // Validate and clean data during migration
            let cleanedEmail = v1.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let validEmail = isValidEmail(cleanedEmail) ? cleanedEmail : ""
            
            let safeName = v1.name.isEmpty ? "Unknown User" : v1.name
            let clampedAge = max(0, min(150, v1.age))
            
            return UserData(
                name: safeName,
                email: validEmail,
                age: clampedAge,
                preferences: UserPreferences.default
            )
        }
    }
}
```

## Security Best Practices

### 1. Use Keychain for Sensitive Data

Store sensitive information in the Keychain:

```swift
// ✅ Good - Sensitive data in Keychain
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let defaultValue: String? = nil
    static let storageType = .keychain(
        keyPrefix: "auth_",
        accessGroup: nil  // Or specify for sharing
    )
}

struct BiometricSettingsStorage: VaultStorable {
    typealias Value = BiometricSettings
    static let defaultValue = BiometricSettings.disabled
    static let storageType = .keychain(keyPrefix: "biometric_")
}

// ❌ Avoid - Sensitive data in UserDefaults
@UserDefault("authToken") var authToken: String = ""  // Not secure!
```

### 2. Implement Proper Access Control

Use appropriate access groups and prefixes:

```swift
// Shared keychain access between app and extension
struct SharedAuthStorage: VaultStorable {
    typealias Value = SharedAuthData
    static let storageType = .keychain(
        keyPrefix: "shared_auth_",
        accessGroup: "group.com.example.keychain"
    )
}

// App-specific sensitive data
struct AppSpecificSecretsStorage: VaultStorable {
    typealias Value = AppSecrets
    static let storageType = .keychain(
        keyPrefix: "app_secrets_",
        accessGroup: nil  // App-specific
    )
}
```

### 3. Sanitize Data Before Storage

Clean and validate data before storing:

```swift
struct UserInputStorage: VaultStorable {
    typealias Value = UserInput
    static let defaultValue = UserInput.empty
    
    // Custom encoder that sanitizes data
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Add custom encoding logic if needed
        return encoder
    }
}

// Sanitize before storing
func saveUserInput(_ input: String) {
    let sanitized = input
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "<script>", with: "")  // Basic XSS prevention
    
    userInput = UserInput(text: sanitized, timestamp: Date())
}
```

## Testing Strategies

### 1. Use Dependency Injection for Testing

Make your storage testable:

```swift
protocol UserDataProviding {
    var userData: UserData { get set }
}

class ProductionUserDataProvider: UserDataProviding, ObservableObject {
    @VaultStored(UserDataStorage.self) var userData
}

class MockUserDataProvider: UserDataProviding, ObservableObject {
    @Published var userData = UserData.test
}

// In your views
struct UserProfileView: View {
    @ObservedObject var dataProvider: any UserDataProviding
    
    var body: some View {
        Text("Hello, \(dataProvider.userData.name)")
    }
}

// In tests
func testUserProfileView() {
    let mockProvider = MockUserDataProvider()
    let view = UserProfileView(dataProvider: mockProvider)
    // Test the view
}
```

### 2. Test Migration Paths

Ensure your migrations work correctly:

```swift
class MigrationTests: XCTestCase {
    func testUserDataMigration() async throws {
        // Test each migration step
        let v1Data = UserDataV1(name: "John", email: "john@example.com")
        let v1Encoded = try JSONEncoder().encode(v1Data)
        
        let migrator = createUserDataMigrator()
        let (migratedData, wasMigrated) = try await migrator.migrate(data: v1Encoded)
        
        XCTAssertTrue(wasMigrated)
        
        let finalData = try JSONDecoder().decode(UserData.self, from: migratedData)
        XCTAssertEqual(finalData.name, "John")
        XCTAssertEqual(finalData.email, "john@example.com")
        XCTAssertNotNil(finalData.preferences)
    }
    
    func testMigrationChain() async throws {
        // Test complete migration chain from oldest to newest
        // V1 -> V2 -> V3 -> Current
    }
}
```

### 3. Test Error Scenarios

Test how your app handles storage errors:

```swift
class ErrorHandlingTests: XCTestCase {
    func testStorageFailureRecovery() async {
        let mockService = FailingMockService()  // Always fails
        
        // Test that app doesn't crash and uses defaults
        let storage = VaultDataStorage<UserData>(
            key: "test",
            defaultValue: UserData.safe,
            service: mockService,
            migrator: DataMigrator.Builder(targetType: UserData.self).build(),
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )
        
        await storage.initializationTask.value
        
        // Should use default value when storage fails
        XCTAssertEqual(storage.value, UserData.safe)
    }
}
```

## Monitoring and Debugging

### 1. Add Comprehensive Logging

Log important storage operations:

```swift
struct LoggingUserDataStorage: VaultStorable {
    typealias Value = UserData
    static let defaultValue = UserData.safe
    
    // Custom encoder with logging
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // Log encoding operations in debug builds
        #if DEBUG
        print("Encoding UserData at \(Date())")
        #endif
        
        return encoder
    }
    
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        #if DEBUG
        print("Decoding UserData at \(Date())")
        #endif
        
        return decoder
    }
}
```

### 2. Monitor Storage Performance

Track storage operation performance:

```swift
class StoragePerformanceMonitor {
    static let shared = StoragePerformanceMonitor()
    private let logger = Logger(subsystem: "StoragePerformance", category: "Monitoring")
    
    func measureOperation<T>(_ operation: String, _ block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("Storage operation '\(operation)' took \(timeElapsed * 1000, specifier: "%.2f")ms")
        }
        
        return try await block()
    }
}

// Usage
func saveUserData(_ data: UserData) async throws {
    try await StoragePerformanceMonitor.shared.measureOperation("saveUserData") {
        userData = data
    }
}
```

## Documentation and Maintenance

### 1. Document Storage Decisions

Document why you chose specific storage types:

```swift
/// User authentication tokens and sensitive session data.
/// 
/// **Storage Type**: Keychain
/// **Reasoning**: Contains sensitive authentication information that should be:
/// - Encrypted at rest
/// - Persistent across app deletions
/// - Protected by device passcode/biometrics
/// - Shareable with app extensions via access group
///
/// **Migration**: None required - tokens are ephemeral and regenerated on login
struct AuthTokenStorage: VaultStorable {
    typealias Value = AuthToken?
    static let defaultValue: AuthToken? = nil
    static let storageType = .keychain(
        keyPrefix: "auth_v1_",
        accessGroup: "group.com.example.auth"
    )
}
```

### 2. Maintain Migration Documentation

Keep track of your data evolution:

```swift
/*
UserData Migration History:

V1 (App Version 1.0-1.2):
- Basic user info: name, email
- Storage: UserDefaults

V2 (App Version 1.3-2.0):
- Added: preferences object
- Added: createdAt timestamp
- Migration: V1 -> V2 adds default preferences

V3 (App Version 2.1+):
- Changed: email validation and cleanup
- Added: profile metadata
- Migration: V2 -> V3 validates email, adds metadata

Future V4 (Planned):
- Split into separate profile and preferences storage
- Migration: V3 -> V4 will split data
*/
```

## Common Anti-Patterns to Avoid

### 1. Don't Store Large Objects in UserDefaults

```swift
// ❌ Avoid
struct LargeImageCacheStorage: VaultStorable {
    typealias Value = [String: Data]  // Could be hundreds of MBs
    static let storageType = .userDefaults()  // Will be very slow
}

// ✅ Better
struct ImageCacheStorage: VaultStorable {
    typealias Value = [String: Data]
    static let storageType = .fileSystem()  // Appropriate for large data
}
```

### 2. Don't Ignore Migration Failures

```swift
// ❌ Avoid - Silent migration failures
static func configure(builder: DataMigrator<UserData>.Builder) {
    builder.register(from: UserDataV1.self, to: UserData.self) { v1 in
        // This might fail but we're not handling it
        return UserData(name: v1.name, email: v1.email)
    }
}

// ✅ Better - Handle potential failures
static func configure(builder: DataMigrator<UserData>.Builder) {
    builder.register(from: UserDataV1.self, to: UserData.self) { v1 in
        // Validate and provide fallbacks
        let safeName = v1.name.isEmpty ? "Unknown User" : v1.name
        let validEmail = isValidEmail(v1.email) ? v1.email : ""
        
        return UserData(name: safeName, email: validEmail)
    }
}
```

### 3. Don't Mix Storage Types Unnecessarily

```swift
// ❌ Avoid - Inconsistent storage for related data
struct UserProfileStorage: VaultStorable {
    typealias Value = UserProfile
    static let storageType = .userDefaults()
}

struct UserPreferencesStorage: VaultStorable {
    typealias Value = UserPreferences
    static let storageType = .fileSystem()  // Why different?
}

// ✅ Better - Consistent storage for related data
struct UserDataStorage: VaultStorable {
    typealias Value = UserData  // Contains both profile and preferences
    static let storageType = .userDefaults()
}
```

## Summary

Following these best practices will help you:

- ✅ Build maintainable and scalable storage solutions
- ✅ Choose appropriate storage types for your data
- ✅ Handle errors gracefully
- ✅ Ensure data security and privacy
- ✅ Write testable code
- ✅ Monitor and debug storage issues
- ✅ Plan for future data evolution

Remember: good storage architecture is about making the right trade-offs between performance, security, maintainability, and user experience.