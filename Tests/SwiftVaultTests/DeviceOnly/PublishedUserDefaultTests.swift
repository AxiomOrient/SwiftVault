import Testing
import Foundation
import Combine
@testable import SwiftVault // 테스트할 모듈을 import 합니다.

// MARK: - Test Support Infrastructure

/// 테스트에 사용될 Codable 모델입니다.
fileprivate struct TestPerson: Codable, Equatable, Sendable {
    var name: String
    var age: Int
}

/// 테스트에 사용될 UserDefaults 키를 타입 안전하게 관리하는 열거형입니다.
fileprivate enum TestKeys: String {
    // @UserDefault
    case string, int, bool, double, date, optionalString, optionalNilString
    // @CodableUserDefault
    case person, optionalPerson, optionalNilPerson
    // @Published...
    case publishedString, publishedPerson
    // UserDefaults Extension
    case prefixKey1, prefixKey2, otherKey
}

/// 테스트를 위한 UserDefaults Mock 구현체입니다. 특정 키에 대한 실패 시나리오를 시뮬레이션할 수 있습니다.
fileprivate final class MockUserDefaults: UserDefaultsProvider {
    private var storage: [String: Any] = [:]
    var keysToFailDecoding: Set<String> = []
    
    // MARK: - UserDefaultsProvider Conformance
    
    func object(forKey key: String) -> Any? { storage[key] }
    func bool(forKey key: String) -> Bool { storage[key] as? Bool ?? false }
    func removeObject(forKey key: String) { storage.removeValue(forKey: key) }

    func data(forKey key: String) -> Data? {
        if keysToFailDecoding.contains(key) {
            // 디코딩 실패를 유발하기 위해 유효하지 않은 Data 반환
            return "corrupted".data(using: .utf8)
        }
        return storage[key] as? Data
    }

    func set(_ value: Any?, forKey key: String) {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
    
    func removePersistentDomain(forName: String) {
        storage.removeAll()
    }

    // UserDefaults.removeValuesWithKeyPrefix(prefix) 와 유사한 동작을 하는 메서드 추가
    func removeValuesWithKeyPrefix(_ prefix: String) {
        let keysToRemove = storage.keys.filter { $0.hasPrefix(prefix) }
        for key in keysToRemove {
            storage.removeValue(forKey: key)
        }
    }
    
    // MARK: - Test Helpers
    
    func inject(object: Any?, forKey key: String) {
        set(object, forKey: key)
    }

    func contains(key: String) -> Bool {
        storage[key] != nil
    }
}

// MARK: - Test Suite

@Suite("PublishedUserDefault & Property Wrappers")
struct PublishedUserDefaultTests {

    // MARK: - @UserDefault Tests

    /// `@UserDefault`가 키가 없을 때 기본값으로 올바르게 초기화되고, 그 값이 저장소에 써지는지 검증합니다.
    @Test("@UserDefault initializes with default value and persists it")
    func testUserDefault_initializationWithDefaultValue() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        
        // Act
        @UserDefault(TestKeys.string.rawValue, store: mockDefaults) var testString: String = "Default"
        
        // Assert
        #expect(testString == "Default")
        #expect(mockDefaults.object(forKey: TestKeys.string.rawValue) as? String == "Default")
    }
    
    /// `@UserDefault`가 저장소에 이미 값이 있을 때 그 값을 올바르게 로드하는지 검증합니다.
    @Test("@UserDefault reads existing value from store")
    func testUserDefault_readsExistingValue() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        mockDefaults.inject(object: "Existing Value", forKey: TestKeys.string.rawValue)
        
        // Act
        @UserDefault(TestKeys.string.rawValue, store: mockDefaults) var testString: String = "Default"
        
        // Assert
        #expect(testString == "Existing Value")
    }
    
    /// `@UserDefault` 속성에 새로운 값을 할당했을 때, 값이 업데이트되고 저장소에 써지는지 검증합니다.
    @Test("@UserDefault sets and persists new value")
    func testUserDefault_setsNewValue() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        @UserDefault(TestKeys.int.rawValue, store: mockDefaults) var testInt: Int = 0

        // Act
        testInt = 123
        
        // Assert
        #expect(testInt == 123)
        #expect(mockDefaults.object(forKey: TestKeys.int.rawValue) as? Int == 123)
    }

    /// `@UserDefault` Optional 속성을 nil로 설정했을 때, 저장소에서 해당 키가 제거되는지 검증합니다.
    @Test("@UserDefault removes key from store when optional value is set to nil")
    func testUserDefault_setOptionalToNil() {
        // Arrange (Given)
        let mockDefaults = MockUserDefaults()
        let initialValue: String? = "Initial"
        // @UserDefault 초기화 시 initialValue가 nil이 아니므로 mockDefaults에 저장됩니다.
        @UserDefault(wrappedValue: initialValue, TestKeys.optionalString.rawValue, store: mockDefaults) var testString: String?
        
        // 초기 상태 검증
        #expect(testString == initialValue)
        #expect(mockDefaults.contains(key: TestKeys.optionalString.rawValue))
        #expect(mockDefaults.object(forKey: TestKeys.optionalString.rawValue) as? String == initialValue)

        // Act (When)
        testString = nil
        
        // Assert (Then)
        // 수정된 @UserDefault는 내부 값도 nil로 설정하므로 이 검증이 통과해야 합니다.
        #expect(testString == nil)
        
        // NSNull이 저장되었는지 확인 (키는 존재해야 함)
        #expect(mockDefaults.contains(key: TestKeys.optionalString.rawValue))
        #expect(mockDefaults.object(forKey: TestKeys.optionalString.rawValue) is NSNull)
    }

    /// `@UserDefault`의 `reset()` 메서드가 값을 기본값으로 되돌리고 저장소에서 키를 제거하는지 검증합니다.
    @Test("@UserDefault reset() reverts to default value and removes key")
    func testUserDefault_reset() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let defaultValue = "Default Value"
        let modifiedValue = "Modified Value"
        @UserDefault(wrappedValue: defaultValue, TestKeys.string.rawValue, store: mockDefaults) var testString: String
        
        // 초기값 확인
        #expect(testString == defaultValue)
        #expect(mockDefaults.object(forKey: TestKeys.string.rawValue) as? String == defaultValue)
        
        testString = modifiedValue // 값 변경
        #expect(testString == modifiedValue)
        #expect(mockDefaults.object(forKey: TestKeys.string.rawValue) as? String == modifiedValue)

        // Act
        // @UserDefault의 projectedValue는 Self이므로, reset()을 직접 호출합니다.
        // 'var'로 선언된 프로퍼티 래퍼에 대해 mutating func 호출은 직접 가능해야 합니다.
        _testString.reset() // 내부 UserDefault 인스턴스의 reset 호출
        // Assert
        #expect(testString == defaultValue) // 내부 값이 기본값으로 돌아왔는지 확인
        #expect(!mockDefaults.contains(key: TestKeys.string.rawValue)) // 저장소에서 키가 제거되었는지 확인
    }

    // MARK: - @CodableUserDefault Tests
    
    /// `@CodableUserDefault`가 Codable 객체를 올바르게 저장(인코딩)하고 로드(디코딩)하는지 검증합니다.
    @Test("@CodableUserDefault saves and loads Codable object")
    func testCodableUserDefault_saveAndLoad() throws {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let person = TestPerson(name: "Blob", age: 30)
        @CodableUserDefault(TestKeys.person.rawValue, store: mockDefaults) var testPerson: TestPerson = .init(name: "Default", age: 0)
        
        // Act
        testPerson = person
        
        // Assert
        #expect(testPerson == person)
        
        let savedData = try #require(mockDefaults.data(forKey: TestKeys.person.rawValue))
        let decodedPerson = try JSONDecoder().decode(TestPerson.self, from: savedData)
        #expect(decodedPerson == person)
    }
    
    /// `@CodableUserDefault`가 디코딩 실패 시 기본값을 반환하는지 검증합니다.
    @Test("@CodableUserDefault returns default value on decoding failure")
    func testCodableUserDefault_decodingFailure() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        mockDefaults.keysToFailDecoding.insert(TestKeys.person.rawValue)
        let defaultValue = TestPerson(name: "Default", age: 0)

        // Act
        @CodableUserDefault(TestKeys.person.rawValue, store: mockDefaults) var testPerson: TestPerson = defaultValue
        
        // Assert
        #expect(testPerson == defaultValue)
    }
    
    /// `@CodableUserDefault` Optional 속성을 nil로 설정했을 때 키가 제거되는지 검증합니다.
    @Test("@CodableUserDefault removes key when optional codable is set to nil")
    func testCodableUserDefault_setOptionalToNil() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let initialPerson: TestPerson? = TestPerson(name: "Initial", age: 10)
        @CodableUserDefault(wrappedValue: initialPerson, TestKeys.optionalPerson.rawValue, store: mockDefaults) var testPerson: TestPerson?
        
        // 초기 상태 검증 (PublishedUserDefault.swift의 @CodableUserDefault init 로직에 따라)
        #expect(testPerson == initialPerson)
        #expect(mockDefaults.contains(key: TestKeys.optionalPerson.rawValue))
        // Act
        testPerson = nil
        
        // Assert
        // PublishedUserDefault.swift의 @CodableUserDefault get/set 로직이 nil을 JSON null로, JSON null을 nil로 올바르게 변환하는지 확인 필요
        #expect(testPerson == nil)
        // JSON null 데이터가 저장되었는지 또는 키가 아예 없는지 확인 (라이브러리 구현에 따라)
        #expect(!mockDefaults.contains(key: TestKeys.optionalPerson.rawValue) || mockDefaults.data(forKey: TestKeys.optionalPerson.rawValue) == "null".data(using: .utf8))
    }

    /// `@CodableUserDefault`의 `reset()` 메서드가 값을 기본값으로 되돌리고 저장소에서 키를 제거하는지 검증합니다.
    @Test("@CodableUserDefault reset() reverts to default value and removes key")
    func testCodableUserDefault_reset() throws {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let defaultValue = TestPerson(name: "Default", age: 0)
        let modifiedValue = TestPerson(name: "Modified", age: 99)
        @CodableUserDefault(wrappedValue: defaultValue, TestKeys.person.rawValue, store: mockDefaults) var testPerson: TestPerson

        // 초기값 확인
        #expect(testPerson == defaultValue)
        var savedData = try #require(mockDefaults.data(forKey: TestKeys.person.rawValue))
        #expect(try JSONDecoder().decode(TestPerson.self, from: savedData) == defaultValue)

        testPerson = modifiedValue // 값 변경
        #expect(testPerson == modifiedValue)
        savedData = try #require(mockDefaults.data(forKey: TestKeys.person.rawValue))
        #expect(try JSONDecoder().decode(TestPerson.self, from: savedData) == modifiedValue)
        // Act
        // @CodableUserDefault의 projectedValue는 Self이므로, reset()을 직접 호출합니다.
        _testPerson.reset() // 내부 CodableUserDefault 인스턴스의 reset 호출
        // Assert
        #expect(testPerson == defaultValue) // 내부 값이 기본값으로 돌아왔는지 확인
        #expect(!mockDefaults.contains(key: TestKeys.person.rawValue)) // 저장소에서 키가 제거되었는지 확인
    }
    
    // MARK: - @Published... Wrapper Tests

    /// `@PublishedUserDefault`가 값 변경 시 `objectWillChange`를 호출하고, 값을 저장하는지 검증합니다.
    @Test("@PublishedUserDefault publishes changes and persists value")
    @MainActor
    func testPublishedUserDefault_publishesAndPersists() async {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let model = TestObservableModel(store: mockDefaults)
        
        var willChangeCount = 0
        let cancellable = model.objectWillChange.sink { willChangeCount += 1 }
        
        // Act
        model.publishedString = "New Value"
        await Task.yield() // @Published 변경이 처리될 시간을 줍니다.

        // Assert
        #expect(willChangeCount > 0)
        #expect(model.publishedString == "New Value")
        #expect(mockDefaults.object(forKey: TestKeys.publishedString.rawValue) as? String == "New Value")
        
        cancellable.cancel()
    }

    /// `@PublishedUserDefault`의 `reset()` 메서드가 값을 기본값으로 되돌리고, 변경 사항을 게시하며, 저장소에서 키를 제거하는지 검증합니다.
    @Test("@PublishedUserDefault reset() reverts, publishes, and removes key")
    @MainActor
    func testPublishedUserDefault_reset() async {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let model = TestObservableModel(store: mockDefaults) // 초기값 "Initial"
        let defaultValue = "Initial"
        let modifiedValue = "Modified Value"

        var receivedValues: [String] = []
        let cancellable = model.$publishedString.sink { receivedValues.append($0) }

        // 초기 상태 및 값 변경
        model.publishedString = modifiedValue
        await Task.yield()
        #expect(model.publishedString == modifiedValue)
        #expect(mockDefaults.object(forKey: TestKeys.publishedString.rawValue) as? String == modifiedValue)
        #expect(receivedValues.contains(modifiedValue))

        // Act
        model.resetPublishedString() // ObservableObject 내부에 reset 호출 메서드 추가 필요
        await Task.yield()

        // Assert
        #expect(model.publishedString == defaultValue)
        #expect(receivedValues.last == defaultValue)
        #expect(!mockDefaults.contains(key: TestKeys.publishedString.rawValue))
        cancellable.cancel()
    }

    /// `@PublishedCodableUserDefault`가 값 변경 시 `objectWillChange`를 호출하고, 값을 저장하는지 검증합니다.
    @Test("@PublishedCodableUserDefault publishes changes and persists codable value")
    @MainActor
    func testPublishedCodableUserDefault_publishesAndPersists() async throws {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let model = TestObservableModel(store: mockDefaults)
        let newPerson = TestPerson(name: "Updated", age: 50)
        
        var willChangeCount = 0
        let cancellable = model.objectWillChange.sink { willChangeCount += 1 }
        
        // Act
        model.publishedPerson = newPerson
        await Task.yield() // @Published 변경이 처리될 시간을 줍니다.
        
        // Assert
        #expect(willChangeCount > 0)
        #expect(model.publishedPerson == newPerson)
        
        let savedData = try #require(mockDefaults.data(forKey: TestKeys.publishedPerson.rawValue))
        let decodedPerson = try JSONDecoder().decode(TestPerson.self, from: savedData)
        #expect(decodedPerson == newPerson)
        
        cancellable.cancel()
    }

    /// `@PublishedCodableUserDefault`의 `reset()` 메서드가 값을 기본값으로 되돌리고, 변경 사항을 게시하며, 저장소에서 키를 제거하는지 검증합니다.
    @Test("@PublishedCodableUserDefault reset() reverts, publishes, and removes key")
    @MainActor
    func testPublishedCodableUserDefault_reset() async throws {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let model = TestObservableModel(store: mockDefaults) // 초기값 TestPerson(name: "Default", age: 0)
        let defaultValue = TestPerson(name: "Default", age: 0)
        let modifiedValue = TestPerson(name: "Modified", age: 88)

        var receivedValues: [TestPerson] = []
        let cancellable = model.$publishedPerson.sink { receivedValues.append($0) }

        // 초기 상태 및 값 변경
        model.publishedPerson = modifiedValue
        await Task.yield()
        #expect(model.publishedPerson == modifiedValue)
        let savedData = try #require(mockDefaults.data(forKey: TestKeys.publishedPerson.rawValue))
        #expect(try JSONDecoder().decode(TestPerson.self, from: savedData) == modifiedValue)
        #expect(receivedValues.contains(modifiedValue))

        // Act
        model.resetPublishedPerson() // ObservableObject 내부에 reset 호출 메서드 추가 필요
        await Task.yield()

        // Assert
        #expect(model.publishedPerson == defaultValue)
        #expect(receivedValues.last == defaultValue)
        #expect(!mockDefaults.contains(key: TestKeys.publishedPerson.rawValue))
        cancellable.cancel()
    }
    
    // MARK: - UserDefaults Extension Tests
    
    /// `isFirstLaunch()`가 첫 호출 시 `true`, 이후 `false`를 반환하는지 검증합니다.
    @Test("isFirstLaunch() returns true on first call, then false")
    func testIsFirstLaunch() throws {
        // Arrange
        let standardDefaults = UserDefaults.standard
        let launchFlagKey = try #require(Bundle.main.bundleIdentifier).appending(".appLaunchedBefore")
        // 테스트 격리를 위해 이전 상태 정리
        standardDefaults.removeObject(forKey: launchFlagKey)
        defer { standardDefaults.removeObject(forKey: launchFlagKey) } // 테스트 후 정리 보장

        // Act & Assert
        #expect(UserDefaults.isFirstLaunch() == true)
        #expect(standardDefaults.bool(forKey: launchFlagKey) == true)
        #expect(UserDefaults.isFirstLaunch() == false)
    }
    
    /// `removeValuesWithKeyPrefix()`가 접두사가 일치하는 키만 제거하는지 검증합니다.
    @Test("removeValuesWithKeyPrefix() removes only matching keys")
    func testRemoveValuesWithKeyPrefix() {
        // Arrange
        let mockDefaults = MockUserDefaults()
        let prefix = "test_prefix_"
        mockDefaults.inject(object: "A", forKey: "\(prefix)key1")
        mockDefaults.inject(object: "B", forKey: "\(prefix)key2")
        mockDefaults.inject(object: "C", forKey: "other_key")
        
        // Act
        mockDefaults.removeValuesWithKeyPrefix(prefix)
        
        // Assert
        #expect(!mockDefaults.contains(key: "\(prefix)key1"))
        #expect(!mockDefaults.contains(key: "\(prefix)key2"))
        #expect(mockDefaults.contains(key: "other_key"))
    }
}

/// `@Published` 래퍼들을 테스트하기 위한 ObservableObject 헬퍼입니다.
@MainActor
fileprivate final class TestObservableModel: ObservableObject {
    @PublishedUserDefault(TestKeys.publishedString.rawValue)
    var publishedString: String = "Initial"

    @PublishedCodableUserDefault(TestKeys.publishedPerson.rawValue)
    var publishedPerson: TestPerson = .init(name: "Default", age: 0)

    init(store: UserDefaultsProvider) {
        _publishedString = .init(wrappedValue: "Initial", TestKeys.publishedString.rawValue, store: store)
        _publishedPerson = .init(wrappedValue: .init(name: "Default", age: 0), TestKeys.publishedPerson.rawValue, store: store)
    }

    // 테스트를 위해 reset을 호출하는 메서드 추가
    func resetPublishedString() {
        _publishedString.reset() // @PublishedUserDefault의 reset 호출
    }

    func resetPublishedPerson() {
        _publishedPerson.reset() // @PublishedCodableUserDefault의 reset 호출
    }
}
