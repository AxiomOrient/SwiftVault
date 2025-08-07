# UserDefault Property Wrappers

SwiftVault provides four property wrappers for seamless UserDefaults integration with modern Swift features including Combine and SwiftUI.

## Overview

| Property Wrapper | Purpose | Features |
|------------------|---------|----------|
| `@UserDefault` | Basic UserDefaults persistence | Type-safe keys, automatic persistence |
| `@CodableUserDefault` | JSON-based persistence for Codable types | Automatic encoding/decoding, error recovery |
| `@PublishedUserDefault` | UserDefaults + Combine publishing | Reactive updates, SwiftUI integration |
| `@PublishedCodableUserDefault` | Codable + Combine publishing | Complex types with reactive updates |

## @UserDefault

Basic property wrapper for UserDefaults persistence of simple types.

### Declaration

```swift
@propertyWrapper
public struct UserDefault<Value> {
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard)
    public var wrappedValue: Value { get set }
    public var projectedValue: Self { get }
    public mutating func reset()
}
```

### Supported Types

- Basic types: `String`, `Int`, `Double`, `Bool`, `Data`, `Date`
- Collections: `Array`, `Dictionary` (with supported element types)
- Optional versions of all supported types

### Usage Examples

```swift
// Basic usage with string keys
@UserDefault("username", store: .standard)
var username: String = "guest"

// Type-safe keys (recommended)
enum UserDefaultsKeys: String, UserDefaultKey {
    case username = "user_name"
    case loginCount = "login_count"
    case isFirstLaunch = "is_first_launch"
}

struct UserSettings {
    @UserDefault(UserDefaultsKeys.username)
    var username: String = "guest"
    
    @UserDefault(UserDefaultsKeys.loginCount)
    var loginCount: Int = 0
    
    @UserDefault(UserDefaultsKeys.isFirstLaunch)
    var isFirstLaunch: Bool = true
}

// Optional values
@UserDefault("lastLoginDate", store: .standard)
var lastLoginDate: Date?

// Collections
@UserDefault("favoriteColors", store: .standard)
var favoriteColors: [String] = ["blue", "green"]

// Custom UserDefaults suite
@UserDefault("sharedSetting", store: UserDefaults(suiteName: "group.com.example.app")!)
var sharedSetting: String = "default"
```

### Methods

#### reset()

Removes the stored value and resets to the default value.

```swift
@UserDefault("counter", store: .standard)
var counter: Int = 0

counter = 42
print(counter) // 42

$counter.reset()
print(counter) // 0 (default value)
```

## @CodableUserDefault

Property wrapper for UserDefaults persistence of Codable types using JSON encoding.

### Declaration

```swift
@propertyWrapper
public struct CodableUserDefault<Value: Codable> {
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard)
    public var wrappedValue: Value { get set }
    public var projectedValue: Self { get }
    public mutating func reset()
}
```

### Supported Types

Any type conforming to `Codable`, including:
- Custom structs and classes
- Enums with associated values
- Complex nested types
- Optional Codable types

### Usage Examples

```swift
// Custom data structures
struct UserProfile: Codable {
    let name: String
    let age: Int
    let preferences: [String: String]
}

@CodableUserDefault("userProfile", store: .standard)
var profile: UserProfile = UserProfile(
    name: "Guest",
    age: 0,
    preferences: [:]
)

// Enums with associated values
enum Theme: Codable {
    case light
    case dark
    case custom(primaryColor: String, secondaryColor: String)
}

@CodableUserDefault("appTheme", store: .standard)
var theme: Theme = .light

// Collections of custom types
struct TodoItem: Codable {
    let id: UUID
    let title: String
    let isCompleted: Bool
}

@CodableUserDefault("todoItems", store: .standard)
var todoItems: [TodoItem] = []

// Optional complex types
@CodableUserDefault("currentProject", store: .standard)
var currentProject: Project?
```

### Error Handling

`@CodableUserDefault` automatically handles encoding/decoding errors:

- **Encoding failures**: Logged but don't prevent app operation
- **Decoding failures**: Corrupted data is removed and default value is used
- **Data corruption**: Automatic recovery with fallback to default

```swift
// This wrapper handles all error scenarios automatically
@CodableUserDefault("complexData", store: .standard)
var complexData: ComplexStruct = ComplexStruct.default

// Even if stored data becomes corrupted, the wrapper will:
// 1. Log the error
// 2. Remove corrupted data
// 3. Return the default value
// 4. Continue normal operation
```

## @PublishedUserDefault

Combines UserDefaults persistence with Combine publishing for reactive programming.

### Declaration

```swift
@propertyWrapper
public struct PublishedUserDefault<Value> {
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard)
    public var projectedValue: UserDefaultPublisher<Value> { get }
    public mutating func reset()
}
```

### Key Features

- Automatic UserDefaults persistence
- Combine publisher for reactive programming
- SwiftUI integration with automatic UI updates
- Thread-safe operations

### Usage with SwiftUI

```swift
class UserSettings: ObservableObject {
    @PublishedUserDefault("username", store: .standard)
    var username: String = "guest"
    
    @PublishedUserDefault("isDarkMode", store: .standard)
    var isDarkMode: Bool = false
    
    @PublishedUserDefault("fontSize", store: .standard)
    var fontSize: Double = 16.0
}

struct ContentView: View {
    @StateObject private var settings = UserSettings()
    
    var body: some View {
        VStack {
            Text("Hello, \(settings.username)!")
                .font(.system(size: settings.fontSize))
            
            TextField("Username", text: $settings.username)
            
            Toggle("Dark Mode", isOn: $settings.isDarkMode)
            
            Slider(value: $settings.fontSize, in: 12...24)
        }
        .preferredColorScheme(settings.isDarkMode ? .dark : .light)
    }
}
```

### Usage with Combine

```swift
class DataManager: ObservableObject {
    @PublishedUserDefault("apiEndpoint", store: .standard)
    var apiEndpoint: String = "https://api.example.com"
    
    @PublishedUserDefault("refreshInterval", store: .standard)
    var refreshInterval: TimeInterval = 60.0
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // React to endpoint changes
        $apiEndpoint
            .sink { [weak self] newEndpoint in
                self?.updateNetworkConfiguration(endpoint: newEndpoint)
            }
            .store(in: &cancellables)
        
        // React to refresh interval changes
        $refreshInterval
            .sink { [weak self] newInterval in
                self?.updateRefreshTimer(interval: newInterval)
            }
            .store(in: &cancellables)
        
        // Combine multiple settings
        Publishers.CombineLatest($apiEndpoint, $refreshInterval)
            .sink { [weak self] endpoint, interval in
                self?.configureNetworking(endpoint: endpoint, refreshInterval: interval)
            }
            .store(in: &cancellables)
    }
}
```

## @PublishedCodableUserDefault

Combines Codable UserDefaults persistence with Combine publishing for complex data types.

### Declaration

```swift
@propertyWrapper
public struct PublishedCodableUserDefault<Value: Codable> {
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaults = UserDefaults.standard)
    public var projectedValue: UserDefaultPublisher<Value> { get }
    public mutating func reset()
}
```

### Usage Examples

```swift
struct UserProfile: Codable {
    let name: String
    let email: String
    let preferences: [String: String]
}

class ProfileManager: ObservableObject {
    @PublishedCodableUserDefault("userProfile", store: .standard)
    var profile: UserProfile = UserProfile(
        name: "Guest",
        email: "",
        preferences: [:]
    )
    
    @PublishedCodableUserDefault("recentSearches", store: .standard)
    var recentSearches: [String] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // React to profile changes
        $profile
            .sink { [weak self] newProfile in
                self?.syncProfileToServer(newProfile)
            }
            .store(in: &cancellables)
        
        // React to search history changes
        $recentSearches
            .sink { [weak self] searches in
                self?.updateSearchSuggestions(searches)
            }
            .store(in: &cancellables)
    }
}

struct ProfileView: View {
    @StateObject private var profileManager = ProfileManager()
    
    var body: some View {
        VStack {
            Text("Welcome, \(profileManager.profile.name)!")
            
            List(profileManager.recentSearches, id: \.self) { search in
                Text(search)
            }
        }
    }
}
```

## UserDefaultKey Protocol

Type-safe key management for UserDefaults.

### Declaration

```swift
public protocol UserDefaultKey {
    var rawValue: String { get }
}

extension String: UserDefaultKey {
    public var rawValue: String { self }
}
```

### Recommended Usage

```swift
enum UserDefaultsKeys: String, UserDefaultKey {
    case username = "user_name"
    case isFirstLaunch = "is_first_launch"
    case userPreferences = "user_preferences"
    case appVersion = "app_version"
    case lastSyncDate = "last_sync_date"
}

// Use throughout your app
@UserDefault(UserDefaultsKeys.username)
var username: String = "guest"

@PublishedUserDefault(UserDefaultsKeys.userPreferences)
var preferences: UserPreferences = UserPreferences.default
```

## UserDefaultsProvider Protocol

Abstraction for UserDefaults access to improve testability.

### Declaration

```swift
public protocol UserDefaultsProvider {
    func object(forKey defaultName: String) -> Any?
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
    func bool(forKey defaultName: String) -> Bool
    func removePersistentDomain(forName domainName: String)
}

extension UserDefaults: UserDefaultsProvider {}
```

### Testing Usage

```swift
class MockUserDefaults: UserDefaultsProvider {
    private var storage: [String: Any] = [:]
    
    func object(forKey key: String) -> Any? {
        return storage[key]
    }
    
    func set(_ value: Any?, forKey key: String) {
        storage[key] = value
    }
    
    func removeObject(forKey key: String) {
        storage.removeValue(forKey: key)
    }
    
    // Implement other required methods...
}

// In tests
let mockDefaults = MockUserDefaults()
@UserDefault("testKey", store: mockDefaults)
var testValue: String = "default"
```

## UserDefaults Extensions

Additional utility methods for UserDefaults management.

### isFirstLaunch()

Determines if this is the first launch of the application.

```swift
if UserDefaults.isFirstLaunch() {
    // Show onboarding or setup initial state
    showOnboarding()
}
```

### clearApplicationStandardUserDefaults()

Clears all UserDefaults values for the current application.

```swift
// Reset all app settings (e.g., during logout)
UserDefaults.clearApplicationStandardUserDefaults()
```

### removeValuesWithKeyPrefix(_:)

Removes all UserDefaults values with keys starting with the specified prefix.

```swift
// Remove all temporary keys
UserDefaults.standard.removeValuesWithKeyPrefix("temp_")

// Remove user-specific settings
UserDefaults.standard.removeValuesWithKeyPrefix("user_\(userID)_")
```

## Performance Considerations

| Wrapper | Read Performance | Write Performance | Memory Usage | Best For |
|---------|------------------|-------------------|--------------|----------|
| `@UserDefault` | Fast | Fast | Low | Simple types, frequent access |
| `@CodableUserDefault` | Medium | Medium | Medium | Complex types, infrequent access |
| `@PublishedUserDefault` | Fast | Fast | Medium | UI-bound simple types |
| `@PublishedCodableUserDefault` | Medium | Medium | High | UI-bound complex types |

## Thread Safety

All property wrappers are thread-safe and can be used from any queue. When used with SwiftUI, UI updates are automatically dispatched to the main queue.

## Best Practices

1. **Use Type-Safe Keys**: Define enums conforming to `UserDefaultKey`
2. **Choose Appropriate Wrapper**: Use the simplest wrapper that meets your needs
3. **Provide Meaningful Defaults**: Always specify sensible default values
4. **Handle Large Objects**: Consider performance impact of large Codable objects
5. **Test with Mocks**: Use `UserDefaultsProvider` for unit testing
6. **Monitor Changes**: Use published variants for reactive programming
7. **Reset When Needed**: Use `reset()` method to clear stored values

## Migration from @AppStorage

SwiftVault property wrappers can be used as drop-in replacements for SwiftUI's `@AppStorage`:

```swift
// SwiftUI @AppStorage
@AppStorage("username") var username: String = "guest"

// SwiftVault equivalent
@PublishedUserDefault("username") var username: String = "guest"
```

**Advantages of SwiftVault:**
- Better error handling
- Type-safe keys
- Testability support
- More flexible storage options
- Automatic data migration support

## See Also

- [VaultStored Property Wrapper](VaultStored.md)
- [Quick Start Guide](QuickStart.md)
- [Testing Guide](Testing.md)
- [Best Practices](BestPractices.md)