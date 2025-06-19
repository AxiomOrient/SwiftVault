import Foundation
import OSLog

public enum SwiftVaultStorageType: Sendable, Hashable {
    case userDefaults(suiteName: String? = nil)
    case keychain(keyPrefix: String = "", accessGroup: String? = nil)
    case fileSystem(location: FileSystemLocation = .default)
    
#if DEBUG
    // Mock service는 ObjectIdentifier를 통해 해싱됩니다.
    case mock(SwiftVaultService)
#endif
    
    public enum FileSystemLocation: Sendable, Hashable {
        case `default`
        case appGroup(identifier: String)
        case custom(directory: FileManager.Path)
    }
    
    public func hash(into hasher: inout Hasher) {
        switch self {
        case .userDefaults(let suiteName):
            hasher.combine("userDefaults")
            hasher.combine(suiteName)
        case .keychain(let keyPrefix, let accessGroup):
            hasher.combine("keychain")
            hasher.combine(keyPrefix)
            hasher.combine(accessGroup)
        case .fileSystem(let location):
            hasher.combine("fileSystem")
            hasher.combine(location)
#if DEBUG
        case .mock(let service):
            // SwiftVaultService는 클래스 프로토콜이 아니므로 AnyObject로 캐스팅할 수 없습니다.
            // 대신, 서비스 객체의 메모리 주소를 나타내는 ObjectIdentifier를 사용합니다.
            let id = ObjectIdentifier(type(of: service))
            hasher.combine(id)
#endif
        }
    }
    
    public static func == (lhs: SwiftVaultStorageType, rhs: SwiftVaultStorageType) -> Bool {
        lhs.hashValue == rhs.hashValue
    }
    
    private static let logger = Logger(subsystem: SwiftVault.Config.defaultLoggerSubsystem, category: "SwiftVaultStorageType")
    
    internal func makeService() throws -> SwiftVaultService {
        switch self {
        case .userDefaults(let suiteName):
            return SwiftVault.userDefaults(suiteName: suiteName)
        case .keychain(let keyPrefix, let accessGroup):
            return SwiftVault.keychain(keyPrefix: keyPrefix, accessGroup: accessGroup)
        case .fileSystem(let location):
            let factoryLocation: SwiftVault.FileSystemLocation
            switch location {
            case .default:
                factoryLocation = .default
            case .appGroup(let identifier):
                factoryLocation = .appGroup(identifier: identifier)
            case .custom(let directory):
                factoryLocation = .custom(directory: directory)
            }
            return try SwiftVault.fileSystem(location: factoryLocation)
#if DEBUG
        case .mock(let service):
            return service
#endif
        }
    }
}
