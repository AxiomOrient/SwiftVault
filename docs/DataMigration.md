# Data Migration

SwiftVault provides a powerful, type-safe data migration system that automatically handles data format changes as your app evolves. The migration system ensures that users never lose data when you update your data models.

## Overview

The migration system consists of:
- **DataMigrator**: Core migration engine
- **Migration Builder**: Fluent API for defining migration paths
- **Automatic Detection**: Detects when migration is needed
- **Chain Migration**: Supports multi-step migration paths
- **Error Recovery**: Graceful handling of migration failures

## DataMigrator

The core migration engine that handles data transformation between versions.

### Declaration

```swift
public struct DataMigrator<TargetModel: AnyCodable & Equatable>: Sendable {
    public final class Builder {
        public init(targetType: TargetModel.Type)
        public func register<From: AnyCodable, To: AnyCodable>(
            from: From.Type,
            to: To.Type,
            converter: @escaping @Sendable (From) -> To
        ) -> Self
        public func build() -> DataMigrator
    }
}
```

### Key Features

- **Type Safety**: Compile-time verification of migration paths
- **Sendable**: Thread-safe migration operations
- **Chain Support**: Automatic chaining of multiple migration steps
- **Error Handling**: Comprehensive error reporting for failed migrations

## Basic Migration Setup

### Simple Migration

```swift
// Version 1 of your data
struct UserSettingsV1: Codable, Equatable {
    let theme: String
}

// Version 2 with additional field
struct UserSettingsV2: Codable, Equatable {
    let theme: String
    let notifications: Bool
}

// Storage definition with migration
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettingsV2
    static let defaultValue = UserSettingsV2(theme: "light", notifications: true)
    
    static func configure(builder: DataMigrator<UserSettingsV2>.Builder) {
        builder.register(from: UserSettingsV1.self, to: UserSettingsV2.self) { v1 in
            UserSettingsV2(theme: v1.theme, notifications: true)
        }
    }
}
```

### Migration with Data Transformation

```swift
// Old format with string-based theme
struct SettingsV1: Codable, Equatable {
    let theme: String  // "light" or "dark"
    let fontSize: Int
}

// New format with enum-based theme
enum Theme: String, Codable {
    case light, dark, auto
}

struct SettingsV2: Codable, Equatable {
    let theme: Theme
    let fontSize: Double  // Changed from Int to Double
}

// Migration with data transformation
static func configure(builder: DataMigrator<SettingsV2>.Builder) {
    builder.register(from: SettingsV1.self, to: SettingsV2.self) { v1 in
        let newTheme: Theme
        switch v1.theme {
        case "light": newTheme = .light
        case "dark": newTheme = .dark
        default: newTheme = .auto
        }
        
        return SettingsV2(
            theme: newTheme,
            fontSize: Double(v1.fontSize)
        )
    }
}
```

## Chain Migration

Handle multiple version upgrades automatically.

### Multi-Step Migration

```swift
// Version history
struct UserDataV1: Codable, Equatable {
    let name: String
}

struct UserDataV2: Codable, Equatable {
    let name: String
    let email: String
}

struct UserDataV3: Codable, Equatable {
    let name: String
    let email: String
    let preferences: [String: String]
}

struct UserDataV4: Codable, Equatable {
    let profile: UserProfile
    let preferences: UserPreferences
}

// Complete migration chain
struct UserDataStorage: VaultStorable {
    typealias Value = UserDataV4
    static let defaultValue = UserDataV4(
        profile: UserProfile.default,
        preferences: UserPreferences.default
    )
    
    static func configure(builder: DataMigrator<UserDataV4>.Builder) {
        builder
            // V1 -> V2: Add email field
            .register(from: UserDataV1.self, to: UserDataV2.self) { v1 in
                UserDataV2(name: v1.name, email: "")
            }
            // V2 -> V3: Add preferences
            .register(from: UserDataV2.self, to: UserDataV3.self) { v2 in
                UserDataV3(name: v2.name, email: v2.email, preferences: [:])
            }
            // V3 -> V4: Restructure data
            .register(from: UserDataV3.self, to: UserDataV4.self) { v3 in
                let profile = UserProfile(name: v3.name, email: v3.email)
                let preferences = UserPreferences(from: v3.preferences)
                return UserDataV4(profile: profile, preferences: preferences)
            }
    }
}
```

### Branching Migration Paths

```swift
// Handle different legacy formats
static func configure(builder: DataMigrator<CurrentFormat>.Builder) {
    // Path 1: From old JSON format
    builder.register(from: LegacyJSONFormat.self, to: CurrentFormat.self) { legacy in
        CurrentFormat(from: legacy.jsonData)
    }
    
    // Path 2: From old plist format
    builder.register(from: LegacyPlistFormat.self, to: CurrentFormat.self) { legacy in
        CurrentFormat(from: legacy.plistData)
    }
    
    // Path 3: From intermediate format
    builder.register(from: IntermediateFormat.self, to: CurrentFormat.self) { intermediate in
        CurrentFormat(upgrading: intermediate)
    }
}
```

## Advanced Migration Patterns

### Conditional Migration

```swift
static func configure(builder: DataMigrator<UserSettings>.Builder) {
    builder.register(from: UserSettingsV2.self, to: UserSettings.self) { v2 in
        // Conditional logic during migration
        let newTheme: Theme
        if v2.theme == "system" {
            newTheme = .auto  // Migrate "system" to new "auto" option
        } else {
            newTheme = Theme(rawValue: v2.theme) ?? .light
        }
        
        return UserSettings(
            theme: newTheme,
            notifications: v2.notifications,
            // Add new field with intelligent default
            fontSize: v2.fontSize ?? (UIDevice.current.userInterfaceIdiom == .pad ? 18.0 : 16.0)
        )
    }
}
```

### Data Validation During Migration

```swift
static func configure(builder: DataMigrator<ValidatedData>.Builder) {
    builder.register(from: UnvalidatedData.self, to: ValidatedData.self) { unvalidated in
        // Validate and clean data during migration
        let cleanedEmail = unvalidated.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let validEmail = cleanedEmail.contains("@") ? cleanedEmail : ""
        
        let clampedAge = max(0, min(150, unvalidated.age))
        
        return ValidatedData(
            name: unvalidated.name.isEmpty ? "Unknown" : unvalidated.name,
            email: validEmail,
            age: clampedAge
        )
    }
}
```

### Complex Data Restructuring

```swift
// Old flat structure
struct FlatUserDataV1: Codable, Equatable {
    let userName: String
    let userEmail: String
    let userAge: Int
    let settingTheme: String
    let settingNotifications: Bool
    let settingFontSize: Double
}

// New hierarchical structure
struct HierarchicalUserData: Codable, Equatable {
    let user: User
    let settings: Settings
}

struct User: Codable, Equatable {
    let name: String
    let email: String
    let age: Int
}

struct Settings: Codable, Equatable {
    let theme: String
    let notifications: Bool
    let fontSize: Double
}

// Migration with restructuring
static func configure(builder: DataMigrator<HierarchicalUserData>.Builder) {
    builder.register(from: FlatUserDataV1.self, to: HierarchicalUserData.self) { flat in
        let user = User(
            name: flat.userName,
            email: flat.userEmail,
            age: flat.userAge
        )
        
        let settings = Settings(
            theme: flat.settingTheme,
            notifications: flat.settingNotifications,
            fontSize: flat.settingFontSize
        )
        
        return HierarchicalUserData(user: user, settings: settings)
    }
}
```

## Migration Process

### How Migration Works

1. **Detection**: SwiftVault attempts to decode data as the current version
2. **Fallback**: If decoding fails, tries each registered legacy version
3. **Chain Execution**: Automatically follows migration chain to current version
4. **Persistence**: Saves migrated data in the new format
5. **Cleanup**: Removes old format data

### Migration Flow Example

```swift
// User has data in V1 format, app expects V3
// Migration chain: V1 -> V2 -> V3

// 1. Try to decode as V3 (current) - fails
// 2. Try to decode as V1 - succeeds
// 3. Apply V1 -> V2 migration
// 4. Apply V2 -> V3 migration
// 5. Save result as V3 format
// 6. Return migrated data
```

## Error Handling

### Migration Errors

```swift
// Migration can fail for various reasons
do {
    let (migratedData, wasMigrated) = try await migrator.migrate(data: oldData)
    if wasMigrated {
        print("Data successfully migrated")
    }
} catch {
    // Handle migration failure
    switch error {
    case MigrationError.decodingFailed:
        // No known version could decode the data
        print("Data format not recognized")
    case MigrationError.pathNotFound(let from):
        // Missing migration path
        print("No migration path from \(from)")
    case MigrationError.finalTypeMismatch:
        // Migration chain produced wrong type
        print("Migration chain error")
    default:
        print("Unknown migration error: \(error)")
    }
}
```

### Graceful Degradation

```swift
struct ResilientStorage: VaultStorable {
    typealias Value = UserData
    static let defaultValue = UserData.safe
    
    static func configure(builder: DataMigrator<UserData>.Builder) {
        // Define migrations...
        builder.register(from: UserDataV1.self, to: UserData.self) { v1 in
            // If migration fails, this will be caught automatically
            // and defaultValue will be used instead
            return UserData(migrating: v1)
        }
    }
}

// SwiftVault automatically handles migration failures:
// 1. Logs the error
// 2. Removes corrupted data
// 3. Uses default value
// 4. App continues normally
```

## Testing Migrations

### Unit Testing Migration Logic

```swift
class MigrationTests: XCTestCase {
    func testUserSettingsMigration() async throws {
        // Create old format data
        let oldSettings = UserSettingsV1(theme: "dark")
        let oldData = try JSONEncoder().encode(oldSettings)
        
        // Create migrator
        let builder = DataMigrator<UserSettingsV2>.Builder(targetType: UserSettingsV2.self)
        builder.register(from: UserSettingsV1.self, to: UserSettingsV2.self) { v1 in
            UserSettingsV2(theme: v1.theme, notifications: true)
        }
        let migrator = builder.build()
        
        // Test migration
        let (migratedData, wasMigrated) = try await migrator.migrate(data: oldData)
        XCTAssertTrue(wasMigrated)
        
        let newSettings = try JSONDecoder().decode(UserSettingsV2.self, from: migratedData)
        XCTAssertEqual(newSettings.theme, "dark")
        XCTAssertTrue(newSettings.notifications)
    }
    
    func testChainMigration() async throws {
        // Test multi-step migration
        let v1Data = UserDataV1(name: "John")
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
        XCTAssertEqual(v3Data.name, "John")
        XCTAssertEqual(v3Data.email, "")
        XCTAssertTrue(v3Data.preferences.isEmpty)
    }
}
```

### Integration Testing

```swift
class IntegrationMigrationTests: XCTestCase {
    func testVaultStoredMigration() async throws {
        // Create mock service with old data
        let mockService = MockSwiftVaultService()
        let oldData = UserSettingsV1(theme: "light")
        let encodedOldData = try JSONEncoder().encode(oldData)
        try await mockService.saveData(encodedOldData, forKey: "test", transactionID: UUID())
        
        // Create storage with migration
        let storage = VaultDataStorage<UserSettingsV2>(
            key: "test",
            defaultValue: UserSettingsV2.default,
            service: mockService,
            migrator: createMigrator(),
            encoder: JSONEncoder(),
            decoder: JSONDecoder()
        )
        
        // Wait for initialization and migration
        await storage.initializationTask.value
        
        // Verify migration occurred
        XCTAssertEqual(storage.value.theme, "light")
        XCTAssertTrue(storage.value.notifications) // Default value from migration
    }
}
```

## Best Practices

### 1. Version Your Data Structures

```swift
// Include version information
struct UserSettingsV3: Codable, Equatable {
    static let version = 3
    let theme: Theme
    let notifications: Bool
    let fontSize: Double
}
```

### 2. Use Semantic Versioning for Keys

```swift
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let key = "user_settings_v3"  // Include version in key
    static let defaultValue = UserSettings.default
}
```

### 3. Plan Migration Paths

```swift
// Document your migration strategy
/*
Migration Path:
V1 (theme: String) 
  -> V2 (theme: String, notifications: Bool)
  -> V3 (theme: Theme, notifications: Bool, fontSize: Double)
  -> V4 (appearance: Appearance, notifications: NotificationSettings)
*/
```

### 4. Test All Migration Paths

```swift
// Test each step in your migration chain
func testAllMigrationPaths() {
    testV1ToV2Migration()
    testV2ToV3Migration()
    testV3ToV4Migration()
    testV1ToV4ChainMigration()  // End-to-end test
}
```

### 5. Handle Edge Cases

```swift
static func configure(builder: DataMigrator<UserSettings>.Builder) {
    builder.register(from: UserSettingsV2.self, to: UserSettings.self) { v2 in
        // Handle edge cases during migration
        let safeTheme = Theme(rawValue: v2.theme) ?? .light
        let safeFontSize = max(8.0, min(72.0, v2.fontSize ?? 16.0))
        
        return UserSettings(
            theme: safeTheme,
            notifications: v2.notifications,
            fontSize: safeFontSize
        )
    }
}
```

### 6. Keep Old Versions for Reference

```swift
// Keep old versions in your codebase for migration support
// Mark them as deprecated but don't delete them

@available(*, deprecated, message: "Use UserSettingsV3 instead")
struct UserSettingsV2: Codable, Equatable {
    let theme: String
    let notifications: Bool
}
```

## Performance Considerations

- **Lazy Migration**: Migration only occurs when data is accessed
- **One-Time Cost**: Migration happens once per data format change
- **Efficient Detection**: Quick format detection before migration
- **Minimal Overhead**: No performance impact for current format data

## Limitations

1. **Forward Compatibility**: Cannot migrate from newer to older versions
2. **Type Safety**: All versions must be known at compile time
3. **Memory Usage**: Large data sets may require significant memory during migration
4. **Atomic Operations**: Migration is all-or-nothing (no partial migrations)

## See Also

- [VaultStored Property Wrapper](VaultStored.md)
- [Storage Types](StorageTypes.md)
- [Best Practices](BestPractices.md)
- [Testing Guide](Testing.md)