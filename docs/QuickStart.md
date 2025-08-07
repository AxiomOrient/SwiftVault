# Quick Start Guide

Get up and running with SwiftVault in minutes. This guide covers the essential concepts and provides practical examples to help you integrate SwiftVault into your app.

## Installation

### Swift Package Manager

Add SwiftVault to your project using Xcode:

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies**
3. Enter the repository URL: `https://github.com/your-org/SwiftVault`
4. Click **Add Package**

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/SwiftVault", from: "1.0.0")
]
```

## Basic Concepts

SwiftVault provides two main approaches for data persistence:

1. **Property Wrappers**: For UserDefaults integration (`@UserDefault`, `@PublishedUserDefault`)
2. **VaultStored**: For advanced multi-backend storage with SwiftUI integration

## Your First SwiftVault Implementation

### 1. Simple UserDefaults Storage

Start with basic UserDefaults persistence:

```swift
import SwiftVault
import SwiftUI

struct ContentView: View {
    @PublishedUserDefault("username", store: .standard)
    var username: String = "Guest"
    
    @PublishedUserDefault("isDarkMode", store: .standard)
    var isDarkMode: Bool = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Hello, \(username)!")
                .font(.title)
            
            TextField("Enter your name", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            Toggle("Dark Mode", isOn: $isDarkMode)
        }
        .padding()
        .preferredColorScheme(isDarkMode ? .dark : .light)
    }
}
```

### 2. Complex Data with VaultStored

For more complex data structures:

```swift
import SwiftVault
import SwiftUI

// Define your data model
struct UserProfile: Codable, Equatable {
    let name: String
    let email: String
    let preferences: UserPreferences
}

struct UserPreferences: Codable, Equatable {
    let theme: String
    let notifications: Bool
    let fontSize: Double
}

// Create a storage definition
struct UserProfileStorage: VaultStorable {
    typealias Value = UserProfile
    
    static let defaultValue = UserProfile(
        name: "Guest",
        email: "",
        preferences: UserPreferences(
            theme: "light",
            notifications: true,
            fontSize: 16.0
        )
    )
}

// Use in your SwiftUI view
struct ProfileView: View {
    @VaultStored(UserProfileStorage.self) var profile
    
    var body: some View {
        Form {
            Section("Profile") {
                TextField("Name", text: $profile.name)
                TextField("Email", text: $profile.email)
            }
            
            Section("Preferences") {
                Picker("Theme", selection: $profile.preferences.theme) {
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                
                Toggle("Notifications", isOn: $profile.preferences.notifications)
                
                Slider(value: $profile.preferences.fontSize, in: 12...24) {
                    Text("Font Size: \(Int(profile.preferences.fontSize))")
                }
            }
        }
    }
}
```

## Common Patterns

### 1. Type-Safe Keys

Instead of using string literals, create type-safe keys:

```swift
enum UserDefaultsKeys: String, UserDefaultKey {
    case username = "user_name"
    case isDarkMode = "is_dark_mode"
    case lastLoginDate = "last_login_date"
}

struct SettingsView: View {
    @PublishedUserDefault(UserDefaultsKeys.username)
    var username: String = "Guest"
    
    @PublishedUserDefault(UserDefaultsKeys.isDarkMode)
    var isDarkMode: Bool = false
    
    var body: some View {
        // Your UI here
    }
}
```

### 2. Reactive Data Updates

Use Combine for reactive programming:

```swift
class DataManager: ObservableObject {
    @PublishedUserDefault("apiEndpoint", store: .standard)
    var apiEndpoint: String = "https://api.example.com"
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // React to endpoint changes
        $apiEndpoint
            .sink { [weak self] newEndpoint in
                self?.updateNetworkConfiguration(endpoint: newEndpoint)
            }
            .store(in: &cancellables)
    }
    
    private func updateNetworkConfiguration(endpoint: String) {
        // Update your network configuration
        print("API endpoint changed to: \(endpoint)")
    }
}
```

### 3. Different Storage Backends

Choose the appropriate storage backend for your data:

```swift
// User preferences - UserDefaults (fast, small data)
struct AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings
    static let defaultValue = AppSettings.default
    static let storageType = SwiftVaultStorageType.userDefaults()
}

// Sensitive data - Keychain (secure)
struct AuthTokenStorage: VaultStorable {
    typealias Value = String?
    static let defaultValue: String? = nil
    static let storageType = SwiftVaultStorageType.keychain(
        keyPrefix: "auth_"
    )
}

// Large data - File System (efficient for big data)
struct DocumentsStorage: VaultStorable {
    typealias Value = [Document]
    static let defaultValue: [Document] = []
    static let storageType = SwiftVaultStorageType.fileSystem()
}
```

## Real-World Example: Todo App

Here's a complete example of a simple todo app using SwiftVault:

```swift
import SwiftVault
import SwiftUI

// MARK: - Data Models

struct TodoItem: Codable, Equatable, Identifiable {
    let id = UUID()
    var title: String
    var isCompleted: Bool
    let createdAt: Date
    
    init(title: String) {
        self.title = title
        self.isCompleted = false
        self.createdAt = Date()
    }
}

struct AppSettings: Codable, Equatable {
    var showCompleted: Bool
    var sortOrder: SortOrder
    
    enum SortOrder: String, Codable, CaseIterable {
        case dateCreated = "date_created"
        case alphabetical = "alphabetical"
        case completion = "completion"
    }
}

// MARK: - Storage Definitions

struct TodoItemsStorage: VaultStorable {
    typealias Value = [TodoItem]
    static let defaultValue: [TodoItem] = []
    static let storageType = SwiftVaultStorageType.fileSystem() // Good for potentially large lists
}

struct AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings
    static let defaultValue = AppSettings(
        showCompleted: true,
        sortOrder: .dateCreated
    )
    static let storageType = SwiftVaultStorageType.userDefaults() // Fast access for settings
}

// MARK: - Views

struct TodoApp: App {
    var body: some Scene {
        WindowGroup {
            TodoListView()
        }
    }
}

struct TodoListView: View {
    @VaultStored(TodoItemsStorage.self) var todoItems
    @VaultStored(AppSettingsStorage.self) var settings
    @State private var newItemTitle = ""
    @State private var showingSettings = false
    
    var filteredAndSortedItems: [TodoItem] {
        let filtered = settings.showCompleted ? todoItems : todoItems.filter { !$0.isCompleted }
        
        switch settings.sortOrder {
        case .dateCreated:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .alphabetical:
            return filtered.sorted { $0.title < $1.title }
        case .completion:
            return filtered.sorted { !$0.isCompleted && $1.isCompleted }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Add new item
                HStack {
                    TextField("New todo item", text: $newItemTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Button("Add") {
                        addNewItem()
                    }
                    .disabled(newItemTitle.isEmpty)
                }
                .padding()
                
                // Todo list
                List {
                    ForEach(filteredAndSortedItems) { item in
                        TodoRowView(item: item) { updatedItem in
                            updateItem(updatedItem)
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
            }
            .navigationTitle("Todo List")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }
    
    private func addNewItem() {
        let newItem = TodoItem(title: newItemTitle)
        todoItems.append(newItem)
        newItemTitle = ""
    }
    
    private func updateItem(_ updatedItem: TodoItem) {
        if let index = todoItems.firstIndex(where: { $0.id == updatedItem.id }) {
            todoItems[index] = updatedItem
        }
    }
    
    private func deleteItems(offsets: IndexSet) {
        let itemsToDelete = offsets.map { filteredAndSortedItems[$0] }
        todoItems.removeAll { item in
            itemsToDelete.contains { $0.id == item.id }
        }
    }
}

struct TodoRowView: View {
    let item: TodoItem
    let onUpdate: (TodoItem) -> Void
    
    var body: some View {
        HStack {
            Button(action: toggleCompletion) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(item.isCompleted ? .green : .gray)
            }
            
            Text(item.title)
                .strikethrough(item.isCompleted)
                .foregroundColor(item.isCompleted ? .gray : .primary)
            
            Spacer()
            
            Text(item.createdAt, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func toggleCompletion() {
        var updatedItem = item
        updatedItem.isCompleted.toggle()
        onUpdate(updatedItem)
    }
}

struct SettingsView: View {
    @VaultStored(AppSettingsStorage.self) var settings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Display") {
                    Toggle("Show Completed Items", isOn: $settings.showCompleted)
                    
                    Picker("Sort Order", selection: $settings.sortOrder) {
                        ForEach(AppSettings.SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
                                .tag(order)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

## Testing Your SwiftVault Code

### Unit Testing with Mocks

```swift
import XCTest
@testable import YourApp

class TodoTests: XCTestCase {
    func testTodoItemCreation() {
        let item = TodoItem(title: "Test Item")
        
        XCTAssertEqual(item.title, "Test Item")
        XCTAssertFalse(item.isCompleted)
        XCTAssertNotNil(item.id)
    }
    
    func testAppSettingsDefaults() {
        let settings = AppSettingsStorage.defaultValue
        
        XCTAssertTrue(settings.showCompleted)
        XCTAssertEqual(settings.sortOrder, .dateCreated)
    }
}
```

### Testing with Mock Storage

```swift
#if DEBUG
class MockTodoStorage: VaultStorable {
    typealias Value = [TodoItem]
    static let defaultValue: [TodoItem] = []
    static let storageType = SwiftVaultStorageType.mock(MockSwiftVaultService())
}

// Use in tests or previews
struct TodoListView_Previews: PreviewProvider {
    static var previews: some View {
        TodoListView()
            // Use mock storage for previews
    }
}
#endif
```

## Next Steps

Now that you have the basics down, explore these advanced features:

1. **[Data Migration](DataMigration.md)**: Handle data model changes gracefully
2. **[Storage Types](StorageTypes.md)**: Learn about different storage backends
3. **[UserDefault Wrappers](UserDefaultWrappers.md)**: Master UserDefaults integration
4. **[Best Practices](BestPractices.md)**: Follow recommended patterns
5. **[Testing Guide](Testing.md)**: Write comprehensive tests

## Common Gotchas

### 1. MainActor Requirements

`@VaultStored` must be used on the main actor:

```swift
// ✅ Correct - in SwiftUI View (automatically @MainActor)
struct MyView: View {
    @VaultStored(MyStorage.self) var data
    // ...
}

// ❌ Incorrect - in background actor
actor BackgroundProcessor {
    @VaultStored(MyStorage.self) var data // Compiler error
}
```

### 2. Equatable Requirement

Your data types must conform to `Equatable`:

```swift
// ✅ Correct
struct UserData: Codable, Equatable {
    let name: String
    let age: Int
}

// ❌ Incorrect - missing Equatable
struct UserData: Codable {
    let name: String
    let age: Int
}
```

### 3. Default Values

Always provide sensible default values:

```swift
// ✅ Correct - meaningful default
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings(
        theme: "system",
        notifications: true,
        fontSize: 16.0
    )
}

// ❌ Avoid - empty or meaningless defaults
static let defaultValue = UserSettings(theme: "", notifications: false, fontSize: 0)
```

## Getting Help

- Check the [API Documentation](README.md) for detailed information
- Review [Best Practices](BestPractices.md) for recommended patterns
- Look at the [Testing Guide](Testing.md) for testing strategies
- File issues on GitHub for bugs or feature requests

## Summary

You've learned how to:

- ✅ Install and import SwiftVault
- ✅ Use `@PublishedUserDefault` for simple data
- ✅ Use `@VaultStored` for complex data structures
- ✅ Choose appropriate storage backends
- ✅ Create type-safe keys
- ✅ Build a complete app with SwiftVault
- ✅ Test your SwiftVault code

SwiftVault makes data persistence in Swift apps simple, type-safe, and powerful. Start with the basics and gradually adopt more advanced features as your needs grow.