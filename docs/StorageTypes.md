# Storage Types

SwiftVault supports multiple storage backends through the `SwiftVaultStorageType` enumeration. Each storage type is optimized for different use cases and provides specific advantages.

## Overview

```swift
public enum SwiftVaultStorageType: Sendable, Hashable {
    case userDefaults(suiteName: String? = nil)
    case keychain(keyPrefix: String = "", accessGroup: String? = nil)
    case fileSystem(location: FileSystemLocation = .default)
    
    #if DEBUG
    case mock(SwiftVaultService)
    #endif
}
```

## UserDefaults Storage

Best for user preferences, app settings, and small data that needs fast access.

### Declaration

```swift
case userDefaults(suiteName: String? = nil)
```

### Parameters

- `suiteName`: Optional UserDefaults suite name. If `nil`, uses `UserDefaults.standard`

### Characteristics

| Aspect | Details |
|--------|---------|
| **Performance** | Very fast read/write |
| **Capacity** | Small data (< 1MB recommended) |
| **Persistence** | Automatic system backup |
| **Sharing** | App Group support via suite names |
| **External Changes** | Real-time notifications |
| **Security** | Not encrypted |

### Usage Examples

```swift
// Standard UserDefaults
struct AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings
    static let defaultValue = AppSettings.default
    static let storageType = SwiftVaultStorageType.userDefaults()
}

// Custom suite for App Group sharing
struct SharedSettingsStorage: VaultStorable {
    typealias Value = SharedSettings
    static let defaultValue = SharedSettings.default
    static let storageType = SwiftVaultStorageType.userDefaults(
        suiteName: "group.com.example.app"
    )
}

// Property wrapper usage
@UserDefault("theme", store: .standard)
var theme: String = "light"

@PublishedUserDefault("notifications", store: UserDefaults(suiteName: "group.com.example.app")!)
var notifications: Bool = true
```

### Best Use Cases

- User preferences (theme, language, etc.)
- App configuration settings
- Feature flags and toggles
- Small cached data
- Cross-app data sharing (with App Groups)

### Limitations

- Not suitable for large data
- No built-in encryption
- Synchronizes with iCloud (may not be desired for all data)
- Limited to property list types for direct access

## Keychain Storage

Best for sensitive data like passwords, tokens, and cryptographic keys.

### Declaration

```swift
case keychain(keyPrefix: String = "", accessGroup: String? = nil)
```

### Parameters

- `keyPrefix`: Prefix added to all keychain keys for organization
- `accessGroup`: Keychain access group for sharing between apps

### Characteristics

| Aspect | Details |
|--------|---------|
| **Performance** | Medium speed (encryption overhead) |
| **Capacity** | Small data (< 8KB per item) |
| **Persistence** | Survives app deletion |
| **Sharing** | Access group support |
| **External Changes** | Limited detection |
| **Security** | Hardware-encrypted |

### Usage Examples

```swift
// Basic keychain storage
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let defaultValue: String? = nil
    static let storageType = SwiftVaultStorageType.keychain()
}

// With key prefix for organization
struct UserCredentialsStorage: VaultStorable {
    typealias Value = Credentials
    static let defaultValue = Credentials.empty
    static let storageType = SwiftVaultStorageType.keychain(
        keyPrefix: "user_creds_"
    )
}

// Shared keychain access group
struct SharedSecretsStorage: VaultStorable {
    typealias Value = SharedSecrets
    static let defaultValue = SharedSecrets.empty
    static let storageType = SwiftVaultStorageType.keychain(
        keyPrefix: "shared_",
        accessGroup: "group.com.example.keychain"
    )
}

// SwiftUI usage
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

### Security Features

- **Hardware Encryption**: Data encrypted using device's Secure Enclave
- **Biometric Protection**: Can require Touch ID/Face ID for access
- **Access Control**: Fine-grained access control options
- **Persistence**: Data survives app deletion and device restore

### Best Use Cases

- Authentication tokens
- User passwords
- API keys and secrets
- Cryptographic keys
- Sensitive user data
- Cross-app credential sharing

### Limitations

- Size limitations (8KB per item)
- Slower than other storage types
- Limited external change detection
- Requires proper access group configuration for sharing

### Keychain Access Groups

```swift
// Configure in your app's entitlements
/*
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)group.com.example.keychain</string>
</array>
*/

// Use in storage definition
struct SharedKeychainStorage: VaultStorable {
    typealias Value = SecretData
    static let storageType = SwiftVaultStorageType.keychain(
        accessGroup: "group.com.example.keychain"
    )
}
```

## File System Storage

Best for large data, documents, and complex data structures.

### Declaration

```swift
case fileSystem(location: FileSystemLocation = .default)
```

### FileSystemLocation Options

```swift
public enum FileSystemLocation: Sendable, Hashable {
    case `default`
    case appGroup(identifier: String)
    case custom(directory: FileManager.Path)
}
```

### Characteristics

| Aspect | Details |
|--------|---------|
| **Performance** | Fast for large data |
| **Capacity** | Limited by device storage |
| **Persistence** | Backed up to iCloud/iTunes |
| **Sharing** | App Group support |
| **External Changes** | Real-time file monitoring |
| **Security** | File system permissions |

### Location Types

#### .default

Uses the app's Application Support directory.

**Path**: `~/Library/Application Support/{BundleID}/SwiftVaultData/`

```swift
struct DocumentsStorage: VaultStorable {
    typealias Value = [Document]
    static let defaultValue: [Document] = []
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .default
    )
}
```

#### .appGroup(identifier:)

Uses an App Group shared container.

```swift
struct SharedDocumentsStorage: VaultStorable {
    typealias Value = [SharedDocument]
    static let defaultValue: [SharedDocument] = []
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .appGroup(identifier: "group.com.example.app")
    )
}
```

**Requirements:**
- App Group capability enabled
- Matching App Group identifier in all sharing apps
- Proper entitlements configuration

#### .custom(directory:)

Uses a custom directory path.

```swift
struct CustomLocationStorage: VaultStorable {
    typealias Value = CustomData
    static let defaultValue = CustomData.empty
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .custom(directory: .url(customURL))
    )
}
```

### Usage Examples

```swift
// Large data storage
struct ImageCacheStorage: VaultStorable {
    typealias Value = [String: Data]  // URL -> Image data
    static let defaultValue: [String: Data] = [:]
    static let storageType = SwiftVaultStorageType.fileSystem()
}

// Document storage with App Group sharing
struct SharedDocumentsStorage: VaultStorable {
    typealias Value = [Document]
    static let defaultValue: [Document] = []
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .appGroup(identifier: "group.com.example.documents")
    )
}

// Custom location for specific needs
struct LogsStorage: VaultStorable {
    typealias Value = [LogEntry]
    static let defaultValue: [LogEntry] = []
    static let storageType = SwiftVaultStorageType.fileSystem(
        location: .custom(directory: .url(logsDirectory))
    )
}

// SwiftUI usage
struct DocumentsView: View {
    @VaultStored(SharedDocumentsStorage.self) var documents
    
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

### File Coordination

SwiftVault uses `NSFileCoordinator` for safe file access:

- **Atomic Operations**: Ensures data consistency
- **Multi-Process Safety**: Safe access from multiple processes
- **External Change Detection**: Monitors file system changes
- **Conflict Resolution**: Handles concurrent access

### Best Use Cases

- Large data sets
- Document storage
- Image/media caches
- Complex data structures
- Cross-app data sharing
- Offline data storage

### Limitations

- Slower than in-memory storage
- Requires disk space
- File system permissions
- Backup implications (iCloud sync)

## Mock Storage (Debug Only)

For testing and development purposes.

### Declaration

```swift
#if DEBUG
case mock(SwiftVaultService)
#endif
```

### Usage Examples

```swift
#if DEBUG
class MockSwiftVaultService: SwiftVaultService {
    private var storage: [String: Data] = [:]
    
    func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
        storage[key] = data
    }
    
    func loadData(forKey key: String) async throws -> Data? {
        return storage[key]
    }
    
    // Implement other required methods...
}

struct MockUserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings.test
    static let storageType = SwiftVaultStorageType.mock(MockSwiftVaultService())
}
#endif

// Conditional usage
struct TestableView: View {
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

## Storage Type Comparison

| Feature | UserDefaults | Keychain | File System |
|---------|--------------|----------|-------------|
| **Speed** | Very Fast | Medium | Fast |
| **Capacity** | Small | Very Small | Large |
| **Security** | None | High | Medium |
| **Sharing** | App Groups | Access Groups | App Groups |
| **Persistence** | App Lifetime | Device Lifetime | App Lifetime |
| **Backup** | iCloud/iTunes | Keychain Sync | iCloud/iTunes |
| **External Changes** | Real-time | Limited | Real-time |
| **Best For** | Preferences | Secrets | Documents |

## Choosing the Right Storage Type

### Decision Matrix

```swift
// Small, non-sensitive data that needs fast access
static let storageType = SwiftVaultStorageType.userDefaults()

// Sensitive data (passwords, tokens, keys)
static let storageType = SwiftVaultStorageType.keychain()

// Large data, documents, complex structures
static let storageType = SwiftVaultStorageType.fileSystem()

// Cross-app sharing needed
static let storageType = SwiftVaultStorageType.userDefaults(
    suiteName: "group.com.example.app"
)
// or
static let storageType = SwiftVaultStorageType.fileSystem(
    location: .appGroup(identifier: "group.com.example.app")
)
```

### Use Case Examples

```swift
// User preferences - UserDefaults
struct ThemeStorage: VaultStorable {
    typealias Value = Theme
    static let storageType = .userDefaults()
}

// Authentication token - Keychain
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let storageType = .keychain(keyPrefix: "auth_")
}

// Large document cache - File System
struct DocumentCacheStorage: VaultStorable {
    typealias Value = [Document]
    static let storageType = .fileSystem()
}

// Shared settings between app and widget - UserDefaults with App Group
struct WidgetSettingsStorage: VaultStorable {
    typealias Value = WidgetSettings
    static let storageType = .userDefaults(suiteName: "group.com.example.widget")
}
```

## Performance Optimization

### UserDefaults Optimization

```swift
// Group related settings together
struct AppSettings: Codable, Equatable {
    let theme: String
    let language: String
    let notifications: Bool
    // Better than separate @UserDefault properties
}

struct AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings
    static let storageType = .userDefaults()
}
```

### File System Optimization

```swift
// Use appropriate data structures for file storage
struct EfficientFileStorage: VaultStorable {
    typealias Value = [String: CacheItem]  // Dictionary for O(1) lookup
    static let storageType = .fileSystem()
}

// Consider data size and access patterns
struct LargeDataStorage: VaultStorable {
    typealias Value = LargeDataSet
    static let storageType = .fileSystem()  // Better than UserDefaults for large data
}
```

### Keychain Optimization

```swift
// Minimize keychain access frequency
struct BatchedSecretsStorage: VaultStorable {
    typealias Value = SecretBundle  // Group secrets together
    static let storageType = .keychain()
}
```

## Error Handling by Storage Type

### UserDefaults Errors

- Encoding/decoding failures
- Suite access issues
- Synchronization conflicts

### Keychain Errors

- Access denied (biometric/passcode required)
- Item not found
- Keychain locked
- Access group configuration issues

### File System Errors

- Disk space insufficient
- Permission denied
- File corruption
- Directory creation failures
- App Group container unavailable

## Best Practices

1. **Choose Appropriate Type**: Match storage type to data characteristics
2. **Use App Groups**: For cross-app data sharing
3. **Handle Errors Gracefully**: Each storage type has specific failure modes
4. **Consider Performance**: UserDefaults for frequent access, File System for large data
5. **Security First**: Use Keychain for sensitive data
6. **Test All Types**: Ensure your app works with all configured storage types
7. **Monitor Storage Usage**: Be aware of capacity limitations

## See Also

- [SwiftVault Factory](SwiftVault.md)
- [VaultStored Property Wrapper](VaultStored.md)
- [Best Practices](BestPractices.md)
- [Quick Start Guide](QuickStart.md)