# SwiftVaultService Protocol

The `SwiftVaultService` protocol defines the core interface for all storage backends in SwiftVault. It provides a unified API for data persistence operations across different storage types.

## Protocol Definition

```swift
public protocol SwiftVaultService: Sendable {
    func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws
    func loadData(forKey key: String) async throws -> Data?
    func remove(forKey key: String) async throws
    func exists(forKey key: String) async -> Bool
    func clearAll() async throws
    nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> { get }
}
```

## Methods

### saveData(_:forKey:transactionID:)

Saves raw data to the storage backend with a transaction identifier.

```swift
func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws
```

**Parameters:**
- `data`: The raw data to store
- `key`: The unique identifier for the data
- `transactionID`: A unique identifier for this transaction

**Throws:** `SwiftVaultError` if the save operation fails

**Usage:**
```swift
let userData = try JSONEncoder().encode(user)
let transactionID = UUID()
try await service.saveData(userData, forKey: "current_user", transactionID: transactionID)
```

**Transaction ID Purpose:**
- Prevents echo notifications when monitoring external changes
- Enables conflict resolution in multi-process scenarios
- Provides audit trail for data modifications

### loadData(forKey:)

Loads raw data from the storage backend.

```swift
func loadData(forKey key: String) async throws -> Data?
```

**Parameters:**
- `key`: The unique identifier for the data

**Returns:** The stored data, or `nil` if no data exists for the key

**Throws:** `SwiftVaultError` if the load operation fails

**Usage:**
```swift
if let userData = try await service.loadData(forKey: "current_user") {
    let user = try JSONDecoder().decode(User.self, from: userData)
    print("Loaded user: \(user.name)")
} else {
    print("No user data found")
}
```

### remove(forKey:)

Removes data associated with the specified key.

```swift
func remove(forKey key: String) async throws
```

**Parameters:**
- `key`: The unique identifier for the data to remove

**Throws:** `SwiftVaultError` if the removal operation fails

**Usage:**
```swift
try await service.remove(forKey: "temporary_data")
```

**Note:** Removing a non-existent key is not considered an error and will complete successfully.

### exists(forKey:)

Checks whether data exists for the specified key.

```swift
func exists(forKey key: String) async -> Bool
```

**Parameters:**
- `key`: The unique identifier to check

**Returns:** `true` if data exists for the key, `false` otherwise

**Usage:**
```swift
if await service.exists(forKey: "user_preferences") {
    let preferences = try await service.loadData(forKey: "user_preferences")
    // Process existing preferences
} else {
    // Set up default preferences
    let defaultPrefs = createDefaultPreferences()
    try await service.saveData(defaultPrefs, forKey: "user_preferences", transactionID: UUID())
}
```

**Performance Note:** This method is optimized for each storage backend and is generally faster than loading data just to check existence.

### clearAll()

Removes all data managed by this service instance.

```swift
func clearAll() async throws
```

**Throws:** `SwiftVaultError` if the clear operation fails

**Usage:**
```swift
// Clear all app data (e.g., during logout)
try await service.clearAll()
```

**⚠️ Warning:** This operation is irreversible and will remove all data. Use with caution.

**Scope:** The exact scope depends on the storage backend:
- **UserDefaults**: Removes all keys in the specified suite
- **Keychain**: Removes all items with the specified key prefix
- **File System**: Removes all files in the specified directory

## Properties

### externalChanges

An async stream that emits notifications when data changes externally.

```swift
nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> { get }
```

**Returns:** An async stream of change notifications

**Stream Elements:**
- `key`: The key that changed, or `nil` for bulk changes
- `transactionID`: The transaction ID of the change, or `nil` if unknown

**Usage:**
```swift
// Monitor all external changes
Task {
    for await (key, transactionID) in service.externalChanges {
        if let key = key {
            print("Key '\(key)' changed externally")
            // Reload specific data
        } else {
            print("Bulk change detected")
            // Reload all data
        }
    }
}

// Monitor specific key changes
Task {
    for await (key, transactionID) in service.externalChanges {
        guard key == "user_preferences" else { continue }
        
        // Reload user preferences
        if let data = try? await service.loadData(forKey: "user_preferences") {
            let preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
            await updateUI(with: preferences)
        }
    }
}
```

**Change Detection by Backend:**
- **UserDefaults**: Uses `UserDefaults.didChangeNotification`
- **Keychain**: Limited external change detection
- **File System**: Uses `NSFilePresenter` for file system monitoring

## Implementation Notes

### Thread Safety

All `SwiftVaultService` implementations are thread-safe and conform to `Sendable`. Methods can be called from any queue, and the service handles internal synchronization.

### Error Handling

All throwing methods use `SwiftVaultError` for consistent error reporting. Common error scenarios:

- **Network/IO Errors**: Wrapped in appropriate `SwiftVaultError` cases
- **Permission Errors**: Reported as `.backendError` or specific error types
- **Data Corruption**: Handled gracefully with fallback mechanisms

### Performance Characteristics

| Operation | UserDefaults | Keychain | File System |
|-----------|--------------|----------|-------------|
| Save | Fast | Medium | Medium |
| Load | Fast | Medium | Fast |
| Exists | Fast | Medium | Fast |
| Remove | Fast | Medium | Fast |
| Clear All | Fast | Slow | Medium |
| External Changes | Real-time | Limited | Real-time |

## Usage Patterns

### Basic CRUD Operations

```swift
let service = SwiftVault.userDefaults()

// Create/Update
let user = User(name: "John", email: "john@example.com")
let userData = try JSONEncoder().encode(user)
try await service.saveData(userData, forKey: "current_user", transactionID: UUID())

// Read
if let userData = try await service.loadData(forKey: "current_user") {
    let user = try JSONDecoder().decode(User.self, from: userData)
    print("Current user: \(user.name)")
}

// Delete
try await service.remove(forKey: "current_user")
```

### Reactive Data Monitoring

```swift
class DataManager {
    private let service: SwiftVaultService
    private var monitoringTask: Task<Void, Never>?
    
    init(service: SwiftVaultService) {
        self.service = service
        startMonitoring()
    }
    
    private func startMonitoring() {
        monitoringTask = Task {
            for await (key, transactionID) in service.externalChanges {
                await handleExternalChange(key: key, transactionID: transactionID)
            }
        }
    }
    
    private func handleExternalChange(key: String?, transactionID: UUID?) async {
        // Handle external changes
        if let key = key {
            await reloadData(for: key)
        } else {
            await reloadAllData()
        }
    }
    
    deinit {
        monitoringTask?.cancel()
    }
}
```

### Batch Operations

```swift
// Save multiple items
let items = ["item1": data1, "item2": data2, "item3": data3]
let transactionID = UUID()

for (key, data) in items {
    try await service.saveData(data, forKey: key, transactionID: transactionID)
}

// Check multiple items
let keys = ["item1", "item2", "item3"]
let existingKeys = await keys.asyncFilter { key in
    await service.exists(forKey: key)
}
```

## Best Practices

1. **Use Transaction IDs**: Always provide meaningful transaction IDs for change tracking
2. **Handle Optionals**: Always check for `nil` when loading data
3. **Monitor Changes**: Use `externalChanges` for reactive data updates
4. **Batch Operations**: Group related operations for better performance
5. **Error Handling**: Always handle potential errors in async operations
6. **Resource Management**: Cancel monitoring tasks when no longer needed

## See Also

- [SwiftVault Factory](SwiftVault.md)
- [Error Handling](SwiftVaultError.md)
- [Storage Types](StorageTypes.md)
- [Best Practices](BestPractices.md)