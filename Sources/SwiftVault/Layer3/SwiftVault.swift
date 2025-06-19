import Foundation
import OSLog

/// `SwiftVaultService` 인스턴스를 생성하기 위한 정적 팩토리 메서드를 제공하는 열거형입니다.
public enum SwiftVault {
    
    /// 파일 시스템 저장 위치를 명시하기 위한 열거형입니다.
    public enum FileSystemLocation: Sendable, Hashable {
        /// 앱의 Application Support 디렉토리 내에 라이브러리가 관리하는 기본 경로를 사용합니다.
        case `default`
        
        /// 지정된 App Group 식별자를 사용하여 공유 컨테이너 경로를 사용합니다.
        case appGroup(identifier: String)
        
        /// 사용자가 직접 지정한 커스텀 디렉토리 경로를 사용합니다.
        case custom(directory: FileManager.Path)
    }
    
    // MARK: - Service Factories
    
    /// `SwiftVaultUserDefaultsService`의 새 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - suiteName: 사용할 `UserDefaults` suite의 이름입니다. `nil`이면 `UserDefaults.standard`가 사용됩니다.
    ///   - loggerSubsystem: 로깅에 사용할 서브시스템 이름입니다.
    /// - Returns: 설정된 `SwiftVaultService` 인스턴스입니다.
    public static func userDefaults(
        suiteName: String? = nil,
        loggerSubsystem: String = Config.defaultLoggerSubsystem
    ) -> SwiftVaultService {
        return SwiftVaultUserDefaultsService(
            suiteName: suiteName,
            loggerSubsystem: loggerSubsystem
        )
    }
    
    /// `SwiftVaultFileSystemService`의 새 인스턴스를 생성합니다. 이 서비스는 `NSFileCoordinator`를 사용하여 항상 안전하게 파일에 접근합니다.
    ///
    /// - Parameters:
    ///   - location: 데이터를 저장할 위치입니다 (`.default`, `.appGroup`, `.custom`). 기본값은 `.default`입니다.
    ///   - loggerSubsystem: 로깅에 사용할 서브시스템 이름입니다.
    /// - Returns: 설정된 `SwiftVaultService` 인스턴스입니다.
    /// - Throws: `SwiftVaultError` 등 서비스 초기화 중 발생할 수 있는 오류입니다.
    public static func fileSystem(
        location: FileSystemLocation = .default,
        loggerSubsystem: String = Config.defaultLoggerSubsystem
    ) throws -> SwiftVaultService {
        let directoryToUse: FileManager.Path
        
        switch location {
        case .default:
            do {
                let appSupportURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let bundleID = Bundle.main.bundleIdentifier ?? Config.defaultBundleIDFallback
                let defaultDirURL = appSupportURL.appendingPathComponent(bundleID, isDirectory: true)
                    .appendingPathComponent(Config.defaultSwiftVaultDirectoryName, isDirectory: true)
                directoryToUse = .url(defaultDirURL)
            } catch {
                throw SwiftVaultError.backendError(
                    reason: "Could not create default directory path for SwiftVaultFileSystemService",
                    underlyingError: error
                )
            }
            
        case .appGroup(let identifier):
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
                throw SwiftVaultError.appGroupContainerUnavailable(
                    appGroupId: identifier,
                    underlyingError: NSError(domain: "SwiftVaultError", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Could not find App Group container. Check your project's capabilities and ensure the App Group Identifier is correct."])
                )
            }
            directoryToUse = .url(containerURL)
            
        case .custom(let directory):
            directoryToUse = directory
        }
        
        return try SwiftVaultFileSystemService(
            baseDirectory: directoryToUse,
            loggerSubsystem: loggerSubsystem
        )
    }
    
    /// `SwiftVaultKeychainService`의 새 인스턴스를 생성합니다.
    ///
    /// - Parameters:
    ///   - keyPrefix: 키체인에 저장될 모든 키 앞에 추가될 접두사입니다.
    ///   - accessGroup: 키체인 접근 그룹입니다.
    ///   - loggerSubsystem: 로깅에 사용할 서브시스템 이름입니다.
    /// - Returns: 설정된 `SwiftVaultService` 인스턴스입니다.
    public static func keychain(
        keyPrefix: String = "",
        accessGroup: String? = nil,
        loggerSubsystem: String = Config.defaultLoggerSubsystem
    ) -> SwiftVaultService {
        return SwiftVaultKeychainService(
            keyPrefix: keyPrefix,
            accessGroup: accessGroup,
            loggerSubsystem: loggerSubsystem
        )
    }
    
    // MARK: - Configuration
    
    public enum Config {
        /// 로깅에 사용될 기본 서브시스템 이름입니다.
        public static let defaultLoggerSubsystem: String = Bundle.main.bundleIdentifier ?? "com.axiomorient.SwiftVault.Default"
        
        /// Bundle Identifier를 가져올 수 없을 때 사용될 대체 값입니다.
        static let defaultBundleIDFallback: String = "com.unknown.app"
        
        /// 파일 시스템 저장소의 기본 디렉토리 이름입니다.
        static let defaultSwiftVaultDirectoryName: String = "SwiftVaultData"
    }
}
