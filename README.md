# SwiftVault

**The next-generation data persistence framework. Safe, Simple, and Powerful.**

`SwiftVault` is a data persistence library designed from the ground up for Swift's modern concurrency model (`async/await`, `actor`). It helps you store and manage `Codable` types in `UserDefaults`, `Keychain`, and the `FileSystem` with incredible simplicity and safety.

Say goodbye to the pain of complex setups, data races, and difficult migrations. `SwiftVault` makes data persistence easy and enjoyable.

## 📖 Table of Contents

- [✨ Features](#-features)
- [📋 Requirements](#-requirements)
- [📦 Installation](#-installation)
- [🚀 Basic Usage](#-basic-usage)
- [🛠️ Advanced Usage](#️-advanced-usage)
- [🔄 Real-time Sync Between App and Extensions](#-real-time-sync-between-app-and-extensions)
- [🏛️ Architecture and Design Philosophy](#️-architecture-and-design-philosophy)
- [📚 Documentation](#-documentation)
- [🤝 Contributing](#-contributing)
- [📜 License](#-license)

-----

## ✨ Features

  - **Type-Safe**: Manages all your data type-safely through the `Codable` protocol.
  - **Seamless SwiftUI Integration**: The `@VaultStored` property wrapper effortlessly binds data to your SwiftUI views with automatic UI updates.
  - **Multiple Storage Backends**: Choose from and easily switch between `UserDefaults`, `Keychain`, and `FileSystem` as needed.
  - **Powerful Data Migration**: Handles complex data model changes elegantly. Simply register single-step conversion functions, and the library manages the entire migration chain automatically.
  - **Concurrency-Safe by Design**: Built on `actor` to prevent data races at the source.
  - **Process-Safe**: Uses `NSFileCoordinator` to protect your data from corruption when accessed by multiple processes, such as in App Groups.
  - **Pure Swift Concurrency**: Guarantees predictable behavior and perfect compatibility with the latest concurrency model.

## 📋 Requirements

  - **Swift**: 5.10+
  - **Platforms**:
      - iOS 15.0+
      - macOS 12.0+
      - watchOS 8.0+

## 📦 Installation

You can add `SwiftVault` to your project using the Swift Package Manager.

In Xcode, select `File > Add Packages...` and enter the repository URL:

```
https://github.com/AxiomOrient/SwiftVault.git
```

## 🚀 Basic Usage

Using `SwiftVault` is incredibly simple. It only takes two steps.

### Step 1: Define Your Data (`VaultStorable`)

First, define the data you want to store and its configuration (key, default value, storage location) by creating a type that conforms to the `VaultStorable` protocol.

```swift
import SwiftVault
import Foundation

// 1. Define your Codable model
struct AppSettings: Codable, Sendable {
    var isHapticFeedbackEnabled: Bool = true
    var username: String = "Guest"
}

// 2. Define the data's configuration using the VaultStorable protocol
enum AppSettingsStorage: VaultStorable {
    typealias Value = AppSettings

    static let key: String = "com.myapp.settings"
    static let defaultValue: AppSettings = AppSettings()
    
    // We'll use the simplest option: UserDefaults.
    static let storageType: SwiftVaultStorageType = .userDefaults()
    
    // No migration is needed, so we leave the configure function empty.
    static func configure(builder: DataMigrator<AppSettings>.Builder) {}
}
```

### Step 2: Bind to Your View (`@VaultStored`)

Now, just declare the data you defined in your SwiftUI view using the `@VaultStored` property wrapper. The data is loaded automatically and seamlessly bound to your UI.

```swift
import SwiftUI
import SwiftVault

struct SettingsView: View {
    // Connect your data to the view using @VaultStored
    @VaultStored(AppSettingsStorage.self) private var settings

    var body: some View {
        Form {
            Section(header: Text("General")) {
                // Two-way binding with $settings.isHapticFeedbackEnabled
                Toggle("Haptic Feedback", isOn: $settings.isHapticFeedbackEnabled)
            }
            
            Section(header: Text("User Profile")) {
                TextField("Username", text: $settings.username)
            }
        }
        .navigationTitle("Settings")
    }
}
```

That's it\! When you tap the `Toggle` or type in the `TextField`, the changes are automatically saved to `UserDefaults` after a 300ms debounce. The last state will be persisted even after restarting the app.

## 🛠️ Advanced Usage

### Data Migration

As your app evolves, so will your data models. `SwiftVault` handles complex data migrations with elegance.

**Scenario:** The `UserProfile` model has changed twice, from V1 to V3. All you need to do is define the **single-step conversion logic (`V1 -> V2`, `V2 -> V3`)**. `SwiftVault` handles the rest.

```swift
import SwiftVault
import Foundation

// --- Define data model versions ---
struct UserProfileV1: Codable, Sendable { var name: String }
struct UserProfileV2: Codable, Sendable { var id: UUID; var name: String }
struct UserProfile: Codable, Sendable { var id: UUID; var fullName: String; var email: String? } // Final target model (V3)

// --- Define VaultStorable with migration logic ---
enum UserProfileStorage: VaultStorable {
    typealias Value = UserProfile

    static let key: String = "com.myapp.userprofile"
    static let defaultValue: UserProfile = UserProfile(id: UUID(), fullName: "Anonymous", email: nil)
    static let storageType: SwiftVaultStorageType = .fileSystem()

    /// Register the migration paths.
    static func configure(builder: DataMigrator<UserProfile>.Builder) {
        builder
            // Define how to convert from V1 to V2
            .register(from: UserProfileV1.self, to: UserProfileV2.self) { v1 in
                return UserProfileV2(id: UUID(), name: v1.name)
            }
            // Define how to convert from V2 to V3 (the final version)
            .register(from: UserProfileV2.self, to: UserProfile.self) { v2 in
                return UserProfile(id: v2.id, fullName: v2.name, email: nil)
            }
    }
}
```

Now, when you use `@VaultStored(UserProfileStorage.self)` in your view, `SwiftVault` will automatically execute the `V1 -> V2 -> V3` migration chain if it finds V1 data in storage, safely loading it as the final `UserProfile` type.

### Various Storage Options

You can choose from various storage backends and configurations based on your needs.

#### UserDefaults (with App Groups)

```swift
enum SharedPrefsStorage: VaultStorable {
    // ...
    static let storageType: SwiftVaultStorageType = .userDefaults(
        suiteName: "group.com.myapp.shared" // App Group ID
    )
    // ...
}
```

#### Keychain (for Sensitive Data)

```swift
enum APITokenStorage: VaultStorable {
    // ...
    static let storageType: SwiftVaultStorageType = .keychain(
        keyPrefix: "com.myapp.api.",
        accessGroup: "TEAM_ID.com.myapp.shared" // Keychain Access Group
    )
    // ...
}
```

#### FileSystem (with App Groups)

```swift
enum DocumentCacheStorage: VaultStorable {
    // ...
    static let storageType: SwiftVaultStorageType = .fileSystem(
        location: .appGroup(identifier: "group.com.myapp.documents") // App Group ID
    )
    // ...
}
```

### Usage Without SwiftUI

You can also use the `SwiftVault` service directly outside of SwiftUI views (e.g., in ViewModels, Repositories, or Service layers).

```swift
import SwiftVault

class AuthService {
    private let tokenService: SwiftVaultService
    private let tokenKey = "session_token"

    init() {
        // Create the Keychain service directly
        self.tokenService = SwiftVault.keychain(keyPrefix: "com.myapp.api.")
    }

    /// Saves the token. If nil is passed, the existing token is removed.
    func saveToken(_ token: String?) async {
        do {
            if let token {
                try await tokenService.save(token, forKey: tokenKey)
            } else {
                try await tokenService.remove(forKey: tokenKey)
            }
        } catch {
            print("Failed to update token: \(error)")
        }
    }

    /// Loads the saved token.
    func loadToken() async -> String? {
        do {
            return try await tokenService.load(forKey: tokenKey, as: String.self)
        } catch {
            print("Failed to load token: \(error)")
            return nil
        }
    }
}
```

## 🔄 Real-time Sync Between App and Extensions

`SwiftVault` supports data synchronization between your main app and extensions (e.g., watchOS apps, widgets) using App Groups. The synchronization behavior varies depending on the storage backend.

### `UserDefaults` and `FileSystem` (Real-time Sync)

  - **How It Works**: These two storage backends use a system-wide change notification mechanism. When another process in the same App Group (like a watch app) modifies the data, the operating system broadcasts this change almost instantly.
  - **The Result**: If you change a value in your iOS app, an active watchOS app will detect the change and update its UI **in near real-time**. If you need real-time sync, these two backends are highly recommended.

### `Keychain` (Limited Sync)

  - **How It Works**: Unfortunately, the system does not provide automatic notifications for `Keychain` data changes. To overcome this limitation, `SwiftVault` checks for changes in Keychain data whenever the app becomes active again (i.e., moves from **background to foreground**).
  - **The Result**: Even if you change a Keychain value on your iOS app, a running watchOS app will not detect it immediately. The changes will be reflected only when the app is reactivated, such as when the user returns to the app after visiting the watch face.

## 🏛️ Architecture and Design Philosophy

`SwiftVault` is built on modern software design principles.

  - **Safety First**: It prevents data races at the source using `actor` and `Sendable` and avoids file access conflicts with `NSFileCoordinator`. All public APIs `throw` errors to encourage explicit exception handling.
  - **Simplicity & Clarity**: The `@VaultStored` property wrapper and the `SwiftVault` factory hide complex internal implementations, providing a simple and intuitive API to the user.
  - **Testability**: All core logic relies on the `SwiftVaultService` protocol. You can easily inject mock objects during testing using `SwiftVaultStorageType.mock(service)`.
  - **Pure Swift Concurrency**: Data flow is managed exclusively with pure Swift Concurrency, maximizing predictability and stability.

## � Doccumentation

Comprehensive documentation is available to help you get the most out of SwiftVault:

### 🚀 Getting Started
- **[Quick Start Guide](docs/QuickStart.md)** - Get up and running with SwiftVault in minutes
- **[Best Practices](docs/BestPractices.md)** - Recommended patterns and practices for production apps

### 📖 Core APIs
- **[SwiftVault Factory](docs/SwiftVault.md)** - Main factory for creating storage services
- **[SwiftVaultService Protocol](docs/SwiftVaultService.md)** - Core service protocol and methods
- **[SwiftVaultError](docs/SwiftVaultError.md)** - Comprehensive error handling guide

### 🔧 Property Wrappers
- **[UserDefault Property Wrappers](docs/UserDefaultWrappers.md)** - UserDefaults-based property wrappers (`@UserDefault`, `@PublishedUserDefault`)
- **[VaultStored Property Wrapper](docs/VaultStored.md)** - SwiftUI-integrated storage wrapper with multi-backend support

### 🏗️ Advanced Features
- **[Data Migration](docs/DataMigration.md)** - Automatic data migration system for evolving data models
- **[Storage Types](docs/StorageTypes.md)** - Available storage backends (UserDefaults, Keychain, FileSystem)

### 🧪 Testing & Quality
- **[Testing Guide](docs/Testing.md)** - Comprehensive testing strategies for SwiftVault applications

### 📋 Reference
- **[Complete API Documentation](docs/README.md)** - Full documentation index with all available guides

## 🤝 Contributing

We welcome contributions! Please see our contributing guidelines for more information.

## 📜 License

`SwiftVault` is released under the MIT license.
