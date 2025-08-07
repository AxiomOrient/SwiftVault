# SwiftVaultError

`SwiftVaultError` is a comprehensive error enumeration that represents all possible failures in SwiftVault operations. It provides detailed, categorized error cases with contextual information for debugging and error handling.

## Overview

```swift
public enum SwiftVaultError: Error, LocalizedError, Equatable {
    // Generic Storage Errors
    case encodingFailed(type: String, underlyingError: Error?)
    case decodingFailed(key: String, type: String, underlyingError: Error?)
    case readFailed(key: String, underlyingError: Error?)
    case writeFailed(key: String, underlyingError: Error?)
    case deleteFailed(key: String, underlyingError: Error?)
    case clearAllFailed(underlyingError: Error?)
    case initializationFailed(String)
    case unsupportedOperation(description: String)
    case backendError(reason: String, underlyingError: Error?)
    
    // File System Specific Errors
    case couldNotCreateDirectory(path: String, underlyingError: Error)
    case couldNotSaveFile(path: String, underlyingError: Error)
    case couldNotReadFile(path: String, underlyingError: Error)
    case couldNotDeleteFile(path: String, underlyingError: Error)
    case fileDoesNotExist(path: String)
    case couldNotLocateSystemDirectory(directoryName: String)
    case directoryListingFailed(path: String, underlyingError: Error)
    
    // Synchronization & Coordination Errors
    case appGroupContainerUnavailable(appGroupId: String, underlyingError: Error?)
    case fileCoordinationFailed(description: String, underlyingError: Error?)
    
    // Migration Errors
    case migrationFailed(key: String, underlyingErrors: [Error])
    
    // UserDefaults Specific Errors
    case userDefaultsEncodingFailed(key: String, type: String, underlyingError: Error)
    case userDefaultsDecodingFailed(key: String, type: String, underlyingError: Error)
    case userDefaultsTypeCastingFailed(key: String, expectedType: String, actualType: String)
}
```

## Error Categories

### Generic Storage Errors

These errors can occur across all storage backends.

#### encodingFailed(type:underlyingError:)

Indicates that value encoding failed during a storage operation.

**Parameters:**
- `type`: The type that failed to encode
- `underlyingError`: The original error that caused the encoding failure

**Common Causes:**
- Non-Codable types passed to JSON encoder
- Circular references in object graphs
- Custom encoding logic failures

**Example:**
```swift
do {
    try await service.saveData(invalidData, forKey: "test", transactionID: UUID())
} catch SwiftVaultError.encodingFailed(let type, let underlyingError) {
    print("Failed to encode \(type): \(underlyingError?.localizedDescription ?? "Unknown error")")
}
```

#### decodingFailed(key:type:underlyingError:)

Indicates that value decoding failed during a retrieval operation.

**Parameters:**
- `key`: The key for which decoding failed
- `type`: The expected type that failed to decode
- `underlyingError`: The original error that caused the decoding failure

**Common Causes:**
- Data format changes between app versions
- Corrupted stored data
- Type mismatches

**Example:**
```swift
do {
    let data = try await service.loadData(forKey: "user_profile")
    let user = try JSONDecoder().decode(User.self, from: data!)
} catch SwiftVaultError.decodingFailed(let key, let type, let underlyingError) {
    print("Failed to decode \(type) for key '\(key)': \(underlyingError?.localizedDescription ?? "Unknown error")")
    // Fallback to default value or migration
}
```

#### readFailed(key:underlyingError:)

Indicates that a data read operation failed.

**Parameters:**
- `key`: The key for which the read operation failed
- `underlyingError`: The original error that caused the read failure

#### writeFailed(key:underlyingError:)

Indicates that a data write operation failed.

**Parameters:**
- `key`: The key for which the write operation failed
- `underlyingError`: The original error that caused the write failure

#### deleteFailed(key:underlyingError:)

Indicates that a data deletion operation failed.

**Parameters:**
- `key`: The key for which the deletion failed
- `underlyingError`: The original error that caused the deletion failure

#### clearAllFailed(underlyingError:)

Indicates that a clear all operation failed.

**Parameters:**
- `underlyingError`: The original error that caused the clear operation to fail

#### initializationFailed(String)

Indicates that service initialization failed.

**Parameters:**
- `message`: A descriptive message explaining the initialization failure

#### unsupportedOperation(description:)

Indicates that an unsupported operation was attempted.

**Parameters:**
- `description`: A description of the unsupported operation

#### backendError(reason:underlyingError:)

Indicates a backend-related operation failure.

**Parameters:**
- `reason`: The reason for the backend failure
- `underlyingError`: The original error from the backend system

### File System Specific Errors

These errors are specific to file-based storage operations.

#### couldNotCreateDirectory(path:underlyingError:)

Directory creation failed.

**Parameters:**
- `path`: The directory path that failed to be created
- `underlyingError`: The underlying file system error

#### couldNotSaveFile(path:underlyingError:)

File save operation failed.

**Parameters:**
- `path`: The file path that failed to be saved
- `underlyingError`: The underlying file system error

#### couldNotReadFile(path:underlyingError:)

File read operation failed.

**Parameters:**
- `path`: The file path that failed to be read
- `underlyingError`: The underlying file system error

#### couldNotDeleteFile(path:underlyingError:)

File deletion failed.

**Parameters:**
- `path`: The file path that failed to be deleted
- `underlyingError`: The underlying file system error

#### fileDoesNotExist(path:)

The specified file does not exist.

**Parameters:**
- `path`: The file path that does not exist

**Note:** This can be a normal case for `load` or `remove` operations.

#### couldNotLocateSystemDirectory(directoryName:)

System directory could not be located.

**Parameters:**
- `directoryName`: The name of the system directory that could not be found

#### directoryListingFailed(path:underlyingError:)

Failed to list directory contents.

**Parameters:**
- `path`: The directory path for which listing failed
- `underlyingError`: The underlying file system error

### Synchronization & Coordination Errors

These errors relate to file coordination and app group access.

#### appGroupContainerUnavailable(appGroupId:underlyingError:)

App Group container URL could not be obtained.

**Parameters:**
- `appGroupId`: The App Group identifier that is unavailable
- `underlyingError`: The original error from the system

**Common Causes:**
- App Group not configured in project capabilities
- Incorrect App Group identifier
- Provisioning profile issues

#### fileCoordinationFailed(description:underlyingError:)

NSFileCoordinator operation failed.

**Parameters:**
- `description`: Description of the failed coordination operation
- `underlyingError`: The original coordination error

### Migration Errors

These errors occur during data migration operations.

#### migrationFailed(key:underlyingErrors:)

Data migration failed for all attempted versions.

**Parameters:**
- `key`: The key for which migration failed
- `underlyingErrors`: Array of errors from all migration attempts

### UserDefaults Specific Errors

These errors are specific to UserDefaults operations.

#### userDefaultsEncodingFailed(key:type:underlyingError:)

JSON encoding failed in a UserDefaults operation.

**Parameters:**
- `key`: The UserDefaults key for which encoding failed
- `type`: The type that failed to encode
- `underlyingError`: The original encoding error

#### userDefaultsDecodingFailed(key:type:underlyingError:)

JSON decoding failed in a UserDefaults operation.

**Parameters:**
- `key`: The UserDefaults key for which decoding failed
- `type`: The expected type that failed to decode
- `underlyingError`: The original decoding error

#### userDefaultsTypeCastingFailed(key:expectedType:actualType:)

Type casting failed in a UserDefaults operation.

**Parameters:**
- `key`: The UserDefaults key for which type casting failed
- `expectedType`: The expected type for the cast
- `actualType`: The actual type that was found

## Error Handling Patterns

### Basic Error Handling

```swift
do {
    try await service.saveData(data, forKey: "user_data", transactionID: UUID())
} catch let error as SwiftVaultError {
    switch error {
    case .writeFailed(let key, let underlyingError):
        print("Write failed for key '\(key)': \(underlyingError?.localizedDescription ?? "Unknown")")
    case .encodingFailed(let type, let underlyingError):
        print("Encoding failed for type '\(type)': \(underlyingError?.localizedDescription ?? "Unknown")")
    default:
        print("SwiftVault error: \(error.localizedDescription ?? "Unknown error")")
    }
} catch {
    print("Unexpected error: \(error)")
}
```

### Comprehensive Error Handling

```swift
func handleSwiftVaultError(_ error: SwiftVaultError) {
    switch error {
    // Storage errors
    case .encodingFailed(let type, let underlyingError):
        logError("Encoding failed for \(type)", underlyingError)
        // Fallback: Use default value or skip operation
        
    case .decodingFailed(let key, let type, let underlyingError):
        logError("Decoding failed for key '\(key)', type \(type)", underlyingError)
        // Fallback: Remove corrupted data and use default
        
    case .readFailed(let key, let underlyingError):
        logError("Read failed for key '\(key)'", underlyingError)
        // Fallback: Return default value
        
    case .writeFailed(let key, let underlyingError):
        logError("Write failed for key '\(key)'", underlyingError)
        // Retry or queue for later
        
    // File system errors
    case .couldNotCreateDirectory(let path, let underlyingError):
        logError("Could not create directory at \(path)", underlyingError)
        // Try alternative location
        
    case .appGroupContainerUnavailable(let appGroupId, let underlyingError):
        logError("App Group '\(appGroupId)' unavailable", underlyingError)
        // Fallback to local storage
        
    // Migration errors
    case .migrationFailed(let key, let underlyingErrors):
        logError("Migration failed for key '\(key)'", underlyingErrors.first)
        // Remove corrupted data and use default
        
    default:
        logError("SwiftVault error", error)
    }
}

private func logError(_ message: String, _ underlyingError: Error?) {
    let errorDescription = underlyingError?.localizedDescription ?? "No underlying error"
    print("[\(Date())] \(message): \(errorDescription)")
}
```

### Recovery Strategies

```swift
class ResilientDataManager {
    private let service: SwiftVaultService
    
    func saveUserData(_ user: User) async {
        do {
            let data = try JSONEncoder().encode(user)
            try await service.saveData(data, forKey: "user", transactionID: UUID())
        } catch SwiftVaultError.encodingFailed(let type, _) {
            // Log error and continue with cached data
            print("Failed to encode \(type), using cached data")
        } catch SwiftVaultError.writeFailed(let key, _) {
            // Queue for retry
            await queueForRetry(key: key, data: try! JSONEncoder().encode(user))
        } catch {
            // Unexpected error
            print("Unexpected error saving user data: \(error)")
        }
    }
    
    func loadUserData() async -> User? {
        do {
            guard let data = try await service.loadData(forKey: "user") else {
                return nil
            }
            return try JSONDecoder().decode(User.self, from: data)
        } catch SwiftVaultError.decodingFailed(let key, _, _) {
            // Data corrupted, remove and return nil
            try? await service.remove(forKey: key)
            return nil
        } catch SwiftVaultError.readFailed(_, _) {
            // Storage issue, return cached data if available
            return getCachedUserData()
        } catch {
            print("Unexpected error loading user data: \(error)")
            return nil
        }
    }
}
```

## Error Recovery

SwiftVault implements automatic error recovery in many scenarios:

1. **Corrupted Data**: Automatically removed and replaced with defaults
2. **Encoding Failures**: Logged but don't crash the application
3. **File System Errors**: Trigger fallback mechanisms where possible
4. **Migration Failures**: Fall back to default values after cleanup

## Thread Safety

`SwiftVaultError` is thread-safe and can be used across different queues and actors. All error cases are value types and don't contain mutable state.

## Best Practices

1. **Specific Handling**: Handle specific error cases rather than generic catches
2. **Logging**: Always log errors with sufficient context for debugging
3. **Fallbacks**: Implement fallback strategies for critical operations
4. **User Experience**: Don't expose technical errors to end users
5. **Recovery**: Implement automatic recovery where possible
6. **Testing**: Test error scenarios in your unit tests

## See Also

- [SwiftVault Factory](SwiftVault.md)
- [SwiftVaultService Protocol](SwiftVaultService.md)
- [Best Practices](BestPractices.md)
- [Testing Guide](Testing.md)