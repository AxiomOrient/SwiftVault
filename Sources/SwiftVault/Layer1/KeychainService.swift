import Foundation
import Security

// MARK: - Core Types & Protocols

/// Represents the result of a keychain operation
@frozen
public enum KeychainResult<T: Sendable>: Sendable {
    case success(T)
    case failure(KeychainError)
    
    // Functional programming methods
    public func map<U: Sendable>(_ transform: @Sendable (T) -> U) -> KeychainResult<U> {
        switch self {
        case .success(let value):
            return .success(transform(value))
        case .failure(let error):
            return .failure(error)
        }
    }
    
    public func flatMap<U: Sendable>(_ transform: @Sendable (T) -> KeychainResult<U>) -> KeychainResult<U> {
        switch self {
        case .success(let value):
            return transform(value)
        case .failure(let error):
            return .failure(error)
        }
    }
    
    public var value: T? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }
    
    public var error: KeychainError? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}

// MARK: - Equatable Conformance for Testing

extension KeychainResult: Equatable where T: Equatable {
    public static func == (lhs: KeychainResult<T>, rhs: KeychainResult<T>) -> Bool {
        switch (lhs, rhs) {
        case (.success(let lVal), .success(let rVal)):
            return lVal == rVal
        case (.failure(let lErr), .failure(let rErr)):
            return lErr == rErr
        default:
            return false
        }
    }
}

/// Keychain-specific errors
public struct KeychainError: Error, Sendable, CustomStringConvertible {
    public let code: OSStatus
    public let operation: String
    
    public var description: String {
        "KeychainError(operation: \(operation), code: \(code), message: \(localizedDescription))"
    }
    
    public var localizedDescription: String {
        switch code {
        case errSecSuccess:
            return "Success"
        case errSecItemNotFound:
            return "Item not found"
        case errSecDuplicateItem:
            return "Duplicate item"
        case errSecAuthFailed:
            return "Authentication failed"
        case errSecNoSuchKeychain:
            return "No such keychain"
        case errSecInvalidKeychain:
            return "Invalid keychain"
        case errSecNotAvailable: // Standard OSStatus
            return "Not available"
        case KeychainError.errSecInvalidData: // Custom code
            // Note: Comparing against KeychainError.errSecInvalidData now
            // The OSStatus extension is removed, so we compare against the static property
            return "Invalid data encountered during keychain operation."
        case KeychainError.errSecDecode: // Custom code
            // Note: Comparing against KeychainError.errSecDecode now
            // The OSStatus extension is removed, so we compare against the static property
            return "Failed to decode data from keychain."
        default:
            return "Unknown keychain error"
        }
    }
}

extension KeychainError: Equatable {
    public static func == (lhs: KeychainError, rhs: KeychainError) -> Bool {
        return lhs.code == rhs.code && lhs.operation == rhs.operation
    }
}

public extension KeychainError {
    static let errSecInvalidData: OSStatus = -25321
    static let errSecDecode: OSStatus = -25322
    static let errSecEncodingFailed: OSStatus = -25323 // 예시 코드
}
/// Keychain item accessibility options
public enum KeychainAccessibility: Sendable {
    case whenUnlocked
    case whenUnlockedThisDeviceOnly
    case afterFirstUnlock
    case afterFirstUnlockThisDeviceOnly
    case whenPasscodeSetThisDeviceOnly
    
    fileprivate var rawValue: CFString {
        switch self {
        case .whenUnlocked:
            return kSecAttrAccessibleWhenUnlocked
        case .whenUnlockedThisDeviceOnly:
            return kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlock:
            return kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly:
            return kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenPasscodeSetThisDeviceOnly:
            return kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        }
    }
}

/// Configuration for keychain operations
public struct KeychainConfiguration: Sendable {
    public let service: String
    public let accessGroup: String?
    public let accessibility: KeychainAccessibility
    
    public init(
        service: String,
        accessGroup: String? = nil,
        accessibility: KeychainAccessibility = .whenUnlocked
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessibility = accessibility
    }
}

/// Protocol for keychain operations - enables dependency injection and testing
public protocol KeychainServiceProtocol: Sendable {
    func store<T: Sendable & Codable>(_ item: T, forKey key: String) async -> KeychainResult<Void>
    func retrieve<T: Sendable & Codable>(_ type: T.Type, forKey key: String) async -> KeychainResult<T?>
    func delete(forKey key: String) async -> KeychainResult<Void>
    func exists(forKey key: String) async -> KeychainResult<Bool>
    func allKeys() async -> KeychainResult<[String]>
}

// MARK: - Actor-based Keychain Service Implementation

/// Thread-safe keychain service using Swift 6 Actor
public actor KeychainService: KeychainServiceProtocol {
    
    // MARK: - Private Properties
    
    private let configuration: KeychainConfiguration
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    public init(configuration: KeychainConfiguration) {
        self.configuration = configuration
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }
    
    // MARK: - Public Interface
    
    /// Store a codable item in the keychain
    public func store<T: Sendable & Codable>(_ item: T, forKey key: String) async -> KeychainResult<Void> {
        await withCheckedContinuation { continuation in
            let result = performStoreOperation(item, forKey: key)
            continuation.resume(returning: result)
        }
    }
    
    /// Retrieve a codable item from the keychain
    public func retrieve<T: Sendable & Codable>(_ type: T.Type, forKey key: String) async -> KeychainResult<T?> {
        await withCheckedContinuation { continuation in
            let result = performRetrieveOperation(type, forKey: key)
            continuation.resume(returning: result)
        }
    }
    
    /// Delete an item from the keychain
    public func delete(forKey key: String) async -> KeychainResult<Void> {
        await withCheckedContinuation { continuation in
            let result = performDeleteOperation(forKey: key)
            continuation.resume(returning: result)
        }
    }
    
    /// Check if an item exists in the keychain
    public func exists(forKey key: String) async -> KeychainResult<Bool> {
        await withCheckedContinuation { continuation in
            let result = performExistsOperation(forKey: key)
            continuation.resume(returning: result)
        }
    }
    
    /// Get all keys from the keychain
    public func allKeys() async -> KeychainResult<[String]> {
        await withCheckedContinuation { continuation in
            let result = performAllKeysOperation()
            continuation.resume(returning: result)
        }
    }
}

// MARK: - Private Implementation

private extension KeychainService {
    
    /// Base query builder - DRY principle
    func baseQuery(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecAttrAccount as String: key
        ]
        
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
    
    /// Create store query
    func storeQuery(forKey key: String, data: Data) -> [String: Any] {
        var query = baseQuery(forKey: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = configuration.accessibility.rawValue
        return query
    }
    
    /// Create retrieve query
    func retrieveQuery(forKey key: String) -> [String: Any] {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }
    
    /// Create all keys query
    func allKeysQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: configuration.service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        if let accessGroup = configuration.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        
        return query
    }
    
    /// Perform store operation
    func performStoreOperation<T: Sendable & Codable>(_ item: T, forKey key: String) -> KeychainResult<Void> {
        let data: Data
        do {
            data = try encoder.encode(item)
        } catch {
            // Include the specific encoding error for better diagnostics.
            return .failure(KeychainError(code: errSecParam, operation: "encode item: \(error.localizedDescription)"))
        }
        
        // First, try to add the item.
        // The storeQuery includes accessibility attributes, which is correct for SecItemAdd.
        let addQuery = storeQuery(forKey: key, data: data)
        var status = SecItemAdd(addQuery as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, so update it.
            // For SecItemUpdate, we use baseQuery to identify the item
            // and provide only the attributes to be updated (kSecValueData).
            // Accessibility is typically set on add and not modified during a simple data update this way.
            let updateQuery = baseQuery(forKey: key)
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(updateQuery as CFDictionary, attributesToUpdate as CFDictionary)
            
            // If update was successful, return success. Otherwise, the error from update will be returned.
            return status == errSecSuccess ? .success(()) : .failure(KeychainError(code: status, operation: "update (after duplicate item error)"))
        }
        
        return status == errSecSuccess ? .success(()) : .failure(KeychainError(code: status, operation: "add"))
    }
    
    /// Perform retrieve operation
    func performRetrieveOperation<T: Sendable & Codable>(_ type: T.Type, forKey key: String) -> KeychainResult<T?> {
        let query = retrieveQuery(forKey: key)
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                return .failure(KeychainError(code: KeychainError.errSecInvalidData, operation: "retrieve"))
            }
            
            do {
                let item = try decoder.decode(type, from: data)
                return .success(item)
            } catch {
                return .failure(KeychainError(code: errSecDecode, operation: "decode"))
                // return .failure(KeychainError(code: KeychainError.errSecDecode, operation: "decode"))
            }
            
        case errSecItemNotFound:
            return .success(nil)
            
        default:
            return .failure(KeychainError(code: status, operation: "retrieve"))
        }
    }
    
    /// Perform delete operation
    func performDeleteOperation(forKey key: String) -> KeychainResult<Void> {
        let query = baseQuery(forKey: key)
        let status = SecItemDelete(query as CFDictionary)
        
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return .success(())
        default:
            return .failure(KeychainError(code: status, operation: "delete"))
        }
    }
    
    /// Perform exists operation
    func performExistsOperation(forKey key: String) -> KeychainResult<Bool> {
        let query = baseQuery(forKey: key)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            return .success(true)
        case errSecItemNotFound:
            return .success(false)
        default:
            return .failure(KeychainError(code: status, operation: "exists"))
        }
    }
    
    /// Perform all keys operation
    func performAllKeysOperation() -> KeychainResult<[String]> {
        let query = allKeysQuery()
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        switch status {
        case errSecSuccess:
            guard let items = result as? [[String: Any]] else {
                return .success([])
            }
            
            let keys = items.compactMap { item in
                item[kSecAttrAccount as String] as? String
            }
            
            return .success(keys)
            
        case errSecItemNotFound:
            return .success([])
            
        default:
            return .failure(KeychainError(code: status, operation: "allKeys"))
        }
    }
}

// MARK: - Convenience Extensions

public extension KeychainService {
    
    /// Convenience method for storing strings
    func storeString(_ string: String, forKey key: String) async -> KeychainResult<Void> {
        await store(string, forKey: key)
    }
    
    /// Convenience method for retrieving strings
    func retrieveString(forKey key: String) async -> KeychainResult<String?> {
        await retrieve(String.self, forKey: key)
    }
    
    /// Convenience method for storing data
    func storeData(_ data: Data, forKey key: String) async -> KeychainResult<Void> {
        await store(data, forKey: key)
    }
    
    /// Convenience method for retrieving data
    func retrieveData(forKey key: String) async -> KeychainResult<Data?> {
        await retrieve(Data.self, forKey: key)
    }
}
