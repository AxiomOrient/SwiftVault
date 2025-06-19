import Foundation
import OSLog
import Combine
import SwiftUI

// MARK: - Shared Resources

fileprivate let logger: Logger = Logger(subsystem: "com.axiomorient.common.util", category: "PublishedUserDefaults")
fileprivate let userDefaultsSharedEncoder = JSONEncoder()
fileprivate let userDefaultsSharedDecoder = JSONDecoder()

// MARK: - Protocols

/// `UserDefaults` 접근을 위한 프로토콜로, 테스트 용이성을 높입니다.
public protocol UserDefaultsProvider {
    func object(forKey: String) -> Any?
    func data(forKey: String) -> Data?
    func set(_ value: Any?, forKey: String)
    func removeObject(forKey: String)
    func bool(forKey: String) -> Bool
    func removePersistentDomain(forName: String)
}

extension UserDefaults: UserDefaultsProvider {}

/// `UserDefaults` 키를 타입 안전하게 관리하기 위한 프로토콜입니다.
public protocol UserDefaultKey {
    var rawValue: String { get }
}

extension String: UserDefaultKey {
    public var rawValue: String { self }
}

// MARK: - Error Definition

/// `UserDefaults` 접근 중 발생할 수 있는 오류를 정의합니다.
public enum UserDefaultError: Error, LocalizedError {
    case encodingFailed(key: String, type: String, underlyingError: Error)
    case decodingFailed(key: String, type: String, underlyingError: Error)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(_, let type, let error):
            return "UserDefaults save failed (Type: \(type), Encoding Error): \(error.localizedDescription)"
        case .decodingFailed(_, let type, let error):
            return "UserDefaults load failed (Type: \(type), Decoding Error): \(error.localizedDescription)"
        }
    }
}

// MARK: - @UserDefault Property Wrapper

/// 기본 데이터 타입을 `UserDefaults`에 저장하는 프로퍼티 래퍼입니다.
@propertyWrapper
public struct UserDefault<Value> {
    private let key: String
    private let defaultValue: Value
    private let store: UserDefaultsProvider

    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard) {
        self.defaultValue = defaultValue
        self.key = key.rawValue
        self.store = store

        // 초기화 시, 저장소에 키가 없으면 기본값을 저장합니다.
        if store.object(forKey: self.key) == nil {
            self.wrappedValue = defaultValue
        }
    }

    public var wrappedValue: Value {
        get {
            let object = store.object(forKey: key)
            
            // `NSNull`은 `nil`로 처리합니다.
            if object is NSNull {
                // Value가 Optional 타입으로 캐스팅될 수 있는지 확인하고 nil을 반환합니다.
                // 이렇게 하면 Value가 실제로 Optional 타입일 때만 nil이 반환됩니다.
                // Non-optional 타입에 NSNull이 저장된 경우는 비정상으로 간주하고 defaultValue를 반환할 수 있습니다.
                guard Value.self is ExpressibleByNilLiteral.Type else {
                    logger.warning("Key '\(self.key)': NSNull found for non-optional type '\(String(describing: Value.self))'. Returning defaultValue.")
                    return defaultValue
                }
                return (nil as Any?) as! Value
            }
            
            // 저장된 값이 유효하면 반환합니다.
            if let value = object as? Value {
                return value
            }
            
            // 그 외의 모든 경우(키 없음, 타입 불일치 등)는 기본값을 반환합니다.
            return defaultValue
        }
        set {
            // Optional 타입이며 값이 nil이면, NSNull을 저장하여 명시적으로 nil을 표현합니다.
            if let optional = newValue as? any ExpressibleByNilLiteral, isNil(optional) {
                store.set(NSNull(), forKey: key)
            } else {
                store.set(newValue, forKey: key)
            }
        }
    }

    public var projectedValue: Self {
        get { self }
    }

    /// 저장된 값을 제거하고, 다음 접근 시 기본값으로 초기화되도록 합니다.
    public mutating func reset() {
        store.removeObject(forKey: key)
    }
    
    /// 값이 `Optional.none`인지 확인하는 헬퍼입니다.
    private func isNil(_ value: Any) -> Bool {
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }
}

// MARK: - @CodableUserDefault Property Wrapper

/// `Codable` 타입을 `UserDefaults`에 저장하는 프로퍼티 래퍼입니다.
@propertyWrapper
public struct CodableUserDefault<Value: Codable> {
    private let key: String
    private let defaultValue: Value
    private let store: UserDefaultsProvider

    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard) {
        self.defaultValue = defaultValue
        self.key = key.rawValue
        self.store = store
        
        if store.object(forKey: self.key) == nil {
            self.wrappedValue = defaultValue
        }
    }

    public var wrappedValue: Value {
        get {
            guard let data = store.data(forKey: key) else {
                return defaultValue
            }
            do {
                // Codable은 Optional 타입을 네이티브로 디코딩할 수 있습니다.
                return try userDefaultsSharedDecoder.decode(Value.self, from: data)
            } catch {
                // 디코딩 실패 시 손상된 데이터를 제거하고 기본값을 반환하는 것이 가장 안전합니다.
                logger.error("Failed to decode value for key '\(self.key)', removing corrupted data and returning default. Error: \(error.localizedDescription)")
                store.removeObject(forKey: key)
                return defaultValue
            }
        }
        set {
            do {
                // Optional을 포함한 모든 값을 그대로 인코딩합니다. Optional.none은 'null' 데이터로 인코딩됩니다.
                let encoded = try userDefaultsSharedEncoder.encode(newValue)
                store.set(encoded, forKey: key)
            } catch {
                print("Failed to encode value for key '\(self.key)': \(error.localizedDescription)")
            }
        }
    }

    public var projectedValue: Self {
        get { self }
    }

    public mutating func reset() {
        store.removeObject(forKey: key)
    }
}

// MARK: - UserDefaults Extension

public extension UserDefaults {
    private static var firstLaunchFlagKey: String {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.axiomorient.app.fallback"
        return "\(bundleID).appLaunchedBefore"
    }

    static func isFirstLaunch() -> Bool {
        let key = firstLaunchFlagKey
        let standardDefaults = UserDefaults.standard
        let isFirstLaunch = !standardDefaults.bool(forKey: key)
        
        if isFirstLaunch {
            standardDefaults.set(true, forKey: key)
        }
        return isFirstLaunch
    }
    
    static func clearApplicationStandardUserDefaults() {
        guard let appDomain = Bundle.main.bundleIdentifier else { return }
        UserDefaults.standard.removePersistentDomain(forName: appDomain)
    }
    
    func removeValuesWithKeyPrefix(_ prefix: String) {
        dictionaryRepresentation().keys
            .lazy
            .filter { $0.hasPrefix(prefix) }
            .forEach(removeObject(forKey:))
    }
}

// MARK: - Published Wrappers Foundation

public final class UserDefaultPublisher<Value>: Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    
    fileprivate let subject: CurrentValueSubject<Value, Never>
    
    fileprivate init(_ output: Value) {
        self.subject = .init(output)
    }
    
    public func receive<S: Subscriber>(subscriber: S) where S.Input == Value, S.Failure == Never {
        subject.subscribe(subscriber)
    }
}

// MARK: - @Published... Property Wrappers

@propertyWrapper
public struct PublishedUserDefault<Value> {
    
    /// Publisher를 지연 생성하고 상태를 저장하기 위한 참조 타입 컨테이너입니다.
    private final class PublisherBox {
        var publisher: UserDefaultPublisher<Value>?
        func getOrCreatePublisher(initialValue: Value) -> UserDefaultPublisher<Value> {
            if let publisher = publisher {
                return publisher
            }
            let newPublisher = UserDefaultPublisher(initialValue)
            self.publisher = newPublisher
            return newPublisher
        }
    }
    
    @UserDefault private var storedValue: Value
    private let publisherBox = PublisherBox()
    
    public var projectedValue: UserDefaultPublisher<Value> {
        // getter가 더 이상 mutating이 아니므로, 클로저 캡처 문제를 해결합니다.
        get {
            publisherBox.getOrCreatePublisher(initialValue: storedValue)
        }
    }
    
    @available(*, unavailable, message: "@Published is only available on properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
    
    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped _: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, PublishedUserDefault<Value>>
    ) -> Value where EnclosingSelf.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            object[keyPath: storageKeyPath].storedValue
        }
        set {
            // 제약 조건 덕분에 타입 캐스팅이 불필요합니다.
            object.objectWillChange.send()
            object[keyPath: storageKeyPath].publisherBox.publisher?.subject.send(newValue)
            object[keyPath: storageKeyPath].storedValue = newValue
        }
    }
    
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard) {
        self._storedValue = UserDefault(wrappedValue: defaultValue, key, store: store)
    }

    public mutating func reset() {
        _storedValue.reset() // 내부 @UserDefault의 reset 호출
        // reset 후의 값 (defaultValue)을 publisher에 알립니다.
        // self.storedValue는 get을 통해 현재 _storedValue의 wrappedValue를 가져옵니다.
        publisherBox.publisher?.subject.send(self.storedValue)
    }
}

@propertyWrapper
public struct PublishedCodableUserDefault<Value: Codable> {
    
    private final class PublisherBox {
        var publisher: UserDefaultPublisher<Value>?
        func getOrCreatePublisher(initialValue: Value) -> UserDefaultPublisher<Value> {
            if let publisher = publisher {
                return publisher
            }
            let newPublisher = UserDefaultPublisher(initialValue)
            self.publisher = newPublisher
            return newPublisher
        }
    }
    
    @CodableUserDefault private var storedValue: Value
    private let publisherBox = PublisherBox()
    
    public var projectedValue: UserDefaultPublisher<Value> {
        get {
            publisherBox.getOrCreatePublisher(initialValue: storedValue)
        }
    }
    
    @available(*, unavailable, message: "@Published is only available on properties of classes")
    public var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
    
    public static subscript<EnclosingSelf: ObservableObject>(
        _enclosingInstance object: EnclosingSelf,
        wrapped _: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, PublishedCodableUserDefault<Value>>
    ) -> Value where EnclosingSelf.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            object[keyPath: storageKeyPath].storedValue
        }
        set {
            object.objectWillChange.send()
            object[keyPath: storageKeyPath].publisherBox.publisher?.subject.send(newValue)
            object[keyPath: storageKeyPath].storedValue = newValue
        }
    }
    
    public init(wrappedValue defaultValue: Value, _ key: UserDefaultKey, store: UserDefaultsProvider = UserDefaults.standard) {
        self._storedValue = CodableUserDefault(wrappedValue: defaultValue, key, store: store)
    }

    public mutating func reset() {
        _storedValue.reset() // 내부 @CodableUserDefault의 reset 호출
        publisherBox.publisher?.subject.send(self.storedValue)
    }
}
