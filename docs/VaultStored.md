# @VaultStored Property Wrapper

`@VaultStored` is SwiftVault's most powerful property wrapper, providing SwiftUI integration with automatic data persistence, migration support, and reactive updates across multiple storage backends.

## Overview

```swift
@MainActor
@propertyWrapper
public struct VaultStored<Value: AnyCodable & Equatable>: DynamicProperty {
    public init<D: VaultStorable>(_ definition: D.Type) where D.Value == Value
    public var wrappedValue: Value { get set }
    public var projectedValue: Binding<Value> { get }
}
```

## Key Features

- **Multi-Backend Support**: UserDefaults, Keychain, File System
- **Automatic Migration**: Built-in data migration system
- **SwiftUI Integration**: Native SwiftUI binding support
- **Reactive Updates**: Automatic UI updates on data changes
- **External Change Detection**: Responds to changes from other processes
- **Type Safety**: Compile-time type checking
- **Performance Optimized**: Debounced writes and efficient caching

## VaultStorable Protocol

Define your data storage requirements using the `VaultStorable` protocol.

### Protocol Definition

```swift
public protocol VaultStorable {
    associatedtype Value: AnyCodable & Equatable
    static var key: String { get }
    static var defaultValue: Value { get }
    static var storageType: SwiftVaultStorageType { get }
    static var encoder: JSONEncoder { get }
    static var decoder: JSONDecoder { get }
    static func configure(builder: DataMigrator<Value>.Builder)
}
```

### Default Implementations

```swift
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
```

## Basic Usage

### Simple Data Storage

```swift
import SwiftVault
import SwiftUI

// Define your data model
struct UserSettings: Codable, Equatable {
    let theme: String
    let notifications: Bool
    let fontSize: Double
}

// Create a storage definition
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings(
        theme: "light",
        notifications: true,
        fontSize: 16.0
    )
}

// Use in SwiftUI
struct SettingsView: View {
    @VaultStored(UserSettingsStorage.self) var settings
    
    var body: some View {
        VStack {
            Picker("Theme", selection: $settings.theme) {
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            
            Toggle("Notifications", isOn: $settings.notifications)
            
            Slider(value: $settings.fontSize, in: 12...24) {
                Text("Font Size")
            }
        }
    }
}
```

### Custom Storage Backend

```swift
// Use Keychain for sensitive data
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let defaultValue: String? = nil
    static let storageType = SwiftVaultStorageType.keychain(
        keyPrefix: "auth_",
        accessGroup: nil
    )
}

struct LoginView: View {
    @VaultStored(AuthTokenStorage.self) var authToken
    
    var body: some View {
        VStack {
            if authToken != nil {
                Text("Logged in")
                Button("Logout") {
                    authToken = nil
                }
            } else {
                Button("Login") {
                    authToken = "secure_token_123"
                }
            }
        }
    }
}
```

### File System Storage

```swift
// Store large data in file system
struct DocumentsStorage: VaultStorable {
    typealias Value = [Document]
    static let defaultValue: [Document] = []
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .default
    )
}

struct DocumentsView: View {
    @VaultStored(DocumentsStorage.self) var documents
    
    var body: some View {
        List {
            ForEach(documents) { document in
                DocumentRow(document: document)
            }
        }
        .toolbar {
            Button("Add Document") {
                documents.append(Document.new())
            }
        }
    }
}
```

## Advanced Features

### Custom Keys

```swift
struct CustomKeyStorage: VaultStorable {
    typealias Value = String
    static let key = "custom_storage_key"
    static let defaultValue = "default_value"
}
```

### Custom Encoding/Decoding

```swift
struct CustomEncodingStorage: VaultStorable {
    typealias Value = ComplexData
    static let defaultValue = ComplexData.default
    
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
    
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
```

### App Group Sharing

```swift
struct SharedDataStorage: VaultStorable {
    typealias Value = SharedData
    static let defaultValue = SharedData.empty
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .appGroup(identifier: "group.com.example.app")
    )
}

// Use in main app
struct MainAppView: View {
    @VaultStored(SharedDataStorage.self) var sharedData
    
    var body: some View {
        Text("Shared: \(sharedData.value)")
    }
}

// Use in widget extension
struct WidgetView: View {
    @VaultStored(SharedDataStorage.self) var sharedData
    
    var body: some View {
        Text("Widget: \(sharedData.value)")
    }
}
```

## Data Migration

`@VaultStored` supports automatic data migration when your data models evolve.

### Migration Setup

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

// Current version
struct UserSettings: Codable, Equatable {
    let theme: String
    let notifications: Bool
    let fontSize: Double
}

// Storage with migration
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings(
        theme: "light",
        notifications: true,
        fontSize: 16.0
    )
    
    static func configure(builder: DataMigrator<UserSettings>.Builder) {
        builder
            .register(from: UserSettingsV1.self, to: UserSettingsV2.self) { v1 in
                UserSettingsV2(theme: v1.theme, notifications: true)
            }
            .register(from: UserSettingsV2.self, to: UserSettings.self) { v2 in
                UserSettings(theme: v2.theme, notifications: v2.notifications, fontSize: 16.0)
            }
    }
}
```

### Migration Chain

```swift
// Complex migration chain
static func configure(builder: DataMigrator<CurrentVersion>.Builder) {
    builder
        // V1 -> V2: Add notifications
        .register(from: V1.self, to: V2.self) { v1 in
            V2(theme: v1.theme, notifications: true)
        }
        // V2 -> V3: Add fontSize
        .register(from: V2.self, to: V3.self) { v2 in
            V3(theme: v2.theme, notifications: v2.notifications, fontSize: 16.0)
        }
        // V3 -> V4: Rename theme to appearance
        .register(from: V3.self, to: V4.self) { v3 in
            V4(appearance: v3.theme, notifications: v3.notifications, fontSize: v3.fontSize)
        }
}
```

## External Change Detection

`@VaultStored` automatically detects and responds to external changes.

### Multi-Process Synchronization

```swift
struct SharedCounterStorage: VaultStorable {
    typealias Value = Int
    static let defaultValue = 0
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .appGroup(identifier: "group.com.example.counter")
    )
}

// In main app
struct MainAppView: View {
    @VaultStored(SharedCounterStorage.self) var counter
    
    var body: some View {
        VStack {
            Text("Counter: \(counter)")
            Button("Increment") {
                counter += 1
            }
        }
    }
}

// In widget - automatically updates when main app changes counter
struct CounterWidget: View {
    @VaultStored(SharedCounterStorage.self) var counter
    
    var body: some View {
        Text("Widget Counter: \(counter)")
    }
}
```

## Performance Optimization

### Debounced Writes

`@VaultStored` automatically debounces writes to prevent excessive I/O operations.

```swift
struct FrequentUpdateStorage: VaultStorable {
    typealias Value = String
    static let defaultValue = ""
}

struct SearchView: View {
    @VaultStored(FrequentUpdateStorage.self) var searchText
    @State private var localSearchText = ""
    
    var body: some View {
        TextField("Search", text: $localSearchText)
            .onChange(of: localSearchText) { newValue in
                // This will be debounced automatically
                searchText = newValue
            }
    }
}
```

### Efficient Change Detection

Only actual value changes trigger saves and notifications.

```swift
// This won't trigger unnecessary saves
settings.theme = settings.theme // No change, no save
settings.theme = "dark"         // Change detected, save triggered
```

## Error Handling

`@VaultStored` handles errors gracefully with automatic recovery.

### Automatic Recovery

```swift
struct ResilientStorage: VaultStorable {
    typealias Value = ComplexData
    static let defaultValue = ComplexData.safe
    
    // If data becomes corrupted:
    // 1. Error is logged
    // 2. Corrupted data is removed
    // 3. Default value is used
    // 4. App continues normally
}
```

### Custom Error Handling

```swift
struct CustomErrorHandlingStorage: VaultStorable {
    typealias Value = ImportantData
    static let defaultValue = ImportantData.empty
    
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        // Custom encoding that's more resilient
        return encoder
    }
}
```

## Testing

### Mock Storage for Testing

```swift
#if DEBUG
struct MockUserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings.test
    static let storageType = SwiftVaultStorageType.mock(MockSwiftVaultService())
}
#endif

// In tests
struct TestView: View {
    #if DEBUG
    @VaultStored(MockUserSettingsStorage.self) var settings
    #else
    @VaultStored(UserSettingsStorage.self) var settings
    #endif
    
    var body: some View {
        Text(settings.theme)
    }
}
```

### Unit Testing

```swift
class VaultStoredTests: XCTestCase {
    func testDataPersistence() async {
        let mockService = MockSwiftVaultService()
        
        // Test that data is saved and loaded correctly
        let testData = UserSettings(theme: "dark", notifications: false, fontSize: 18.0)
        
        // Simulate saving
        let encoder = JSONEncoder()
        let data = try encoder.encode(testData)
        try await mockService.saveData(data, forKey: "test", transactionID: UUID())
        
        // Simulate loading
        let loadedData = try await mockService.loadData(forKey: "test")
        let decodedData = try JSONDecoder().decode(UserSettings.self, from: loadedData!)
        
        XCTAssertEqual(testData, decodedData)
    }
}
```

## Best Practices

### 1. Choose Appropriate Storage Types

```swift
// User preferences - UserDefaults
struct PreferencesStorage: VaultStorable {
    typealias Value = UserPreferences
    static let storageType = .userDefaults()
}

// Sensitive data - Keychain
struct CredentialsStorage: VaultStorable {
    typealias Value = Credentials
    static let storageType = .keychain(keyPrefix: "creds_")
}

// Large data - File System
struct DocumentsStorage: VaultStorable {
    typealias Value = [Document]
    static let storageType = .fileSystem()
}
```

### 2. Use Meaningful Default Values

```swift
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings(
        theme: "system",           // Sensible default
        notifications: true,       // Safe default
        fontSize: 16.0            // Standard size
    )
}
```

### 3. Plan for Migration

```swift
// Always version your data structures
struct UserSettingsV3: Codable, Equatable {
    let version: Int = 3  // Include version for future migrations
    let theme: String
    let notifications: Bool
    let fontSize: Double
}
```

### 4. Use Type-Safe Keys

```swift
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let key = "user_settings_v3"  // Include version in key
    static let defaultValue = UserSettings.default
}
```

### 5. Handle Large Objects Carefully

```swift
// For large objects, consider file system storage
struct LargeDataStorage: VaultStorable {
    typealias Value = LargeDataSet
    static let storageType = .fileSystem()  // Better for large data
    static let defaultValue = LargeDataSet.empty
}
```

## Limitations

1. **Value Types Only**: Only supports value types (structs, enums)
2. **Equatable Requirement**: Values must conform to `Equatable`
3. **Codable Requirement**: Values must conform to `Codable`
4. **MainActor Requirement**: Must be used on the main actor
5. **SwiftUI Context**: Designed primarily for SwiftUI applications

## Performance Characteristics

| Storage Type | Read Speed | Write Speed | External Changes | Best For |
|--------------|------------|-------------|------------------|----------|
| UserDefaults | Fast | Fast | Real-time | Small data, preferences |
| Keychain | Medium | Slow | Limited | Sensitive data |
| File System | Fast | Medium | Real-time | Large data, documents |

## See Also

- [UserDefault Property Wrappers](UserDefaultWrappers.md)
- [Data Migration](DataMigration.md)
- [Storage Types](StorageTypes.md)
- [Quick Start Guide](QuickStart.md)
- [Best Practices](BestPractices.md)