# SwiftVault Documentation

SwiftVault is a comprehensive, type-safe data persistence library for Swift applications. It provides multiple storage backends with a unified API, automatic data migration, and seamless integration with SwiftUI and Combine.

## 📚 Documentation Index

### Core APIs
- [SwiftVault Factory](SwiftVault.md) - Main factory for creating storage services
- [SwiftVaultService Protocol](SwiftVaultService.md) - Core service protocol
- [SwiftVaultError](SwiftVaultError.md) - Comprehensive error handling

### Property Wrappers
- [UserDefault Property Wrappers](UserDefaultWrappers.md) - UserDefaults-based property wrappers
- [VaultStored Property Wrapper](VaultStored.md) - SwiftUI-integrated storage wrapper

### Advanced Features
- [Data Migration](DataMigration.md) - Automatic data migration system
- [Storage Types](StorageTypes.md) - Available storage backends

### Guides
- [Quick Start Guide](QuickStart.md) - Get started with SwiftVault
- [Best Practices](BestPractices.md) - Recommended usage patterns
- [Testing Guide](Testing.md) - How to test code using SwiftVault

## 🚀 Quick Example

```swift
import SwiftVault
import SwiftUI

// Define your data model
struct UserSettings: Codable, Equatable {
    let theme: String
    let notifications: Bool
}

// Create a storage definition
struct UserSettingsStorage: VaultStorable {
    typealias Value = UserSettings
    static let defaultValue = UserSettings(theme: "light", notifications: true)
    static let storageType = SwiftVaultStorageType.userDefaults()
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
        }
    }
}
```

## 🏗️ Architecture

SwiftVault follows a layered architecture:

- **Layer 3**: High-level APIs and property wrappers
- **Layer 2**: Service implementations (UserDefaults, Keychain, FileSystem)
- **Layer 1**: Low-level utilities and platform abstractions


## 📄 License

This project is licensed under the MIT License.