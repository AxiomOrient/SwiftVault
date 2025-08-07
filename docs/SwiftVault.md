# SwiftVault Factory

The `SwiftVault` enum provides static factory methods for creating different types of storage services. It's the main entry point for configuring and initializing SwiftVault services.

## Overview

```swift
public enum SwiftVault {
    // Factory methods for creating services
    static func userDefaults(suiteName: String?, loggerSubsystem: String) -> SwiftVaultService
    static func fileSystem(location: FileSystemLocation, loggerSubsystem: String) throws -> SwiftVaultService
    static func keychain(keyPrefix: String, accessGroup: String?, loggerSubsystem: String) -> SwiftVaultService
}
```

## Factory Methods

### userDefaults(suiteName:loggerSubsystem:)

Creates a UserDefaults-based storage service.

```swift
static func userDefaults(
    suiteName: String? = nil,
    loggerSubsystem: String = Config.defaultLoggerSubsystem
) -> SwiftVaultService
```

**Parameters:**
- `suiteName`: The UserDefaults suite name. If `nil`, uses `UserDefaults.standard`
- `loggerSubsystem`: The logging subsystem identifier

**Returns:** A configured `SwiftVaultService` instance

**Example:**
```swift
// Use standard UserDefaults
let service = SwiftVault.userDefaults()

// Use custom suite
let appGroupService = SwiftVault.userDefaults(suiteName: "group.com.example.app")

// Custom logging
let service = SwiftVault.userDefaults(
    suiteName: "com.example.settings",
    loggerSubsystem: "com.example.app.storage"
)
```

### fileSystem(location:loggerSubsystem:)

Creates a file system-based storage service with NSFileCoordinator for safe file access.

```swift
static func fileSystem(
    location: FileSystemLocation = .default,
    loggerSubsystem: String = Config.defaultLoggerSubsystem
) throws -> SwiftVaultService
```

**Parameters:**
- `location`: Where to store files (see FileSystemLocation)
- `loggerSubsystem`: The logging subsystem identifier

**Returns:** A configured `SwiftVaultService` instance

**Throws:** `SwiftVaultError` if service initialization fails

**Example:**
```swift
// Use default location (Application Support)
let service = try SwiftVault.fileSystem()

// Use App Group container
let service = try SwiftVault.fileSystem(
    location: .appGroup(identifier: "group.com.example.app")
)

// Use custom directory
let customURL = FileManager.default.documentsDirectory
let service = try SwiftVault.fileSystem(
    location: .custom(directory: .url(customURL))
)
```

### keychain(keyPrefix:accessGroup:loggerSubsystem:)

Creates a Keychain-based storage service for secure data storage.

```swift
static func keychain(
    keyPrefix: String = "",
    accessGroup: String? = nil,
    loggerSubsystem: String = Config.defaultLoggerSubsystem
) -> SwiftVaultService
```

**Parameters:**
- `keyPrefix`: Prefix added to all keychain keys
- `accessGroup`: Keychain access group for sharing between apps
- `loggerSubsystem`: The logging subsystem identifier

**Returns:** A configured `SwiftVaultService` instance

**Example:**
```swift
// Basic keychain service
let service = SwiftVault.keychain()

// With key prefix for organization
let service = SwiftVault.keychain(keyPrefix: "user_credentials_")

// Shared keychain access group
let service = SwiftVault.keychain(
    keyPrefix: "shared_",
    accessGroup: "group.com.example.keychain"
)
```

## FileSystemLocation

Specifies where file system storage should be located.

```swift
public enum FileSystemLocation: Sendable, Hashable {
    case `default`
    case appGroup(identifier: String)
    case custom(directory: FileManager.Path)
}
```

### Cases

#### `.default`
Uses the app's Application Support directory with a SwiftVault subdirectory.

**Path:** `~/Library/Application Support/{BundleID}/SwiftVaultData/`

#### `.appGroup(identifier:)`
Uses an App Group shared container for data sharing between apps.

**Parameters:**
- `identifier`: The App Group identifier (e.g., "group.com.example.app")

**Requirements:**
- App Group capability must be enabled
- All apps sharing data must have the same App Group identifier

#### `.custom(directory:)`
Uses a custom directory path specified by the developer.

**Parameters:**
- `directory`: A `FileManager.Path` specifying the storage location

## Configuration

### Config

Contains default configuration values used throughout SwiftVault.

```swift
public enum Config {
    static let defaultLoggerSubsystem: String
    static let defaultBundleIDFallback: String
    static let defaultSwiftVaultDirectoryName: String
}
```

**Properties:**
- `defaultLoggerSubsystem`: Default logging subsystem (uses Bundle ID)
- `defaultBundleIDFallback`: Fallback Bundle ID if main Bundle ID is unavailable
- `defaultSwiftVaultDirectoryName`: Default directory name for file storage ("SwiftVaultData")

## Error Handling

Factory methods may throw `SwiftVaultError` in the following cases:

- **File System Service:**
  - `.backendError`: Cannot create default directory
  - `.appGroupContainerUnavailable`: App Group container not accessible
  - `.initializationFailed`: Service initialization failed

**Example Error Handling:**
```swift
do {
    let service = try SwiftVault.fileSystem(
        location: .appGroup(identifier: "group.com.example.app")
    )
} catch SwiftVaultError.appGroupContainerUnavailable(let appGroupId, let underlyingError) {
    print("App Group '\(appGroupId)' not available: \(underlyingError?.localizedDescription ?? "Unknown error")")
} catch {
    print("Failed to create file system service: \(error)")
}
```

## Thread Safety

All factory methods are thread-safe and can be called from any queue. The returned services are also thread-safe and implement the `Sendable` protocol.

## Best Practices

1. **Reuse Services**: Create services once and reuse them throughout your app
2. **Choose Appropriate Storage**: 
   - UserDefaults: User preferences, app settings
   - Keychain: Sensitive data, credentials
   - File System: Large data, complex objects
3. **Use App Groups**: For data sharing between apps or extensions
4. **Custom Logging**: Use meaningful subsystem names for better debugging
5. **Error Handling**: Always handle potential initialization errors for file system services

## See Also

- [SwiftVaultService Protocol](SwiftVaultService.md)
- [Storage Types](StorageTypes.md)
- [Error Handling](SwiftVaultError.md)