import Foundation

/// SwiftVault 작업 중 발생할 수 있는 일반적인 오류를 나타내는 열거형입니다.
/// 이 오류들은 작업의 종류(예: 읽기, 쓰기, 삭제)와 관련된 구체적인 실패 원인을
/// 나타내기 위해 세분화되어 있습니다. 각 케이스는 추가적인 컨텍스트 정보를
/// 제공할 수 있는 연관 값을 포함할 수 있습니다.
public enum SwiftVaultError: Error, LocalizedError, Equatable {
    // MARK: - Generic Storage Errors
    /// 값 인코딩에 실패했을 때 발생하는 오류입니다.
    case encodingFailed(type: String, underlyingError: Error? = nil)
    /// 값 디코딩에 실패했을 때 발생하는 오류입니다.
    case decodingFailed(key: String, type: String, underlyingError: Error? = nil)
    /// 데이터 읽기에 실패했을 때 발생하는 오류입니다.
    case readFailed(key: String, underlyingError: Error? = nil)
    /// 데이터 쓰기에 실패했을 때 발생하는 오류입니다.
    case writeFailed(key: String, underlyingError: Error? = nil)
    /// 데이터 삭제에 실패했을 때 발생하는 오류입니다.
    case deleteFailed(key: String, underlyingError: Error? = nil)
    /// 모든 데이터 삭제에 실패했을 때 발생하는 오류입니다.
    case clearAllFailed(underlyingError: Error? = nil)
    /// 서비스 초기화에 실패했을 때 발생하는 오류입니다.
    case initializationFailed(String)
    /// 지원되지 않는 연산이 시도되었을 때 발생하는 오류입니다.
    case unsupportedOperation(description: String)
    /// 백엔드 관련 작업 실패 시 발생하는 오류입니다.
    case backendError(reason: String, underlyingError: Error? = nil)
    
    // MARK: - File System Specific Errors (from former FileManagerError)
    /// 파일 시스템에서 디렉토리 생성에 실패 시 발생합니다.
    case couldNotCreateDirectory(path: String, underlyingError: Error)
    /// 파일 시스템에서 파일 저장에 실패 시 발생합니다.
    case couldNotSaveFile(path: String, underlyingError: Error)
    /// 파일 시스템에서 파일 읽기에 실패 시 발생합니다.
    case couldNotReadFile(path: String, underlyingError: Error)
    /// 파일 시스템에서 파일 삭제에 실패 시 발생합니다.
    case couldNotDeleteFile(path: String, underlyingError: Error)
    /// 파일 시스템에서 특정 경로에 파일이 존재하지 않을 때 발생하는 오류입니다.
    case fileDoesNotExist(path: String) // Note: This can be a normal case for `load` or `remove` operations.
    /// 파일 시스템에서 시스템 디렉토리 경로를 찾을 수 없을 때 발생하는 오류입니다.
    case couldNotLocateSystemDirectory(directoryName: String) // FileManager.SearchPathDirectory 대신 String으로
    /// 파일 시스템에서 디렉토리 내용 목록을 가져오는 데 실패했을 때 발생하는 오류입니다.
    case directoryListingFailed(path: String, underlyingError: Error)
    
    // MARK: - Synchronization & Coordination Errors
    /// App Group 컨테이너 URL을 가져올 수 없을 때 발생하는 오류입니다.
    case appGroupContainerUnavailable(appGroupId: String, underlyingError: Error? = nil)
    /// NSFileCoordinator를 사용한 파일 작업 조정에 실패했을 때 발생하는 오류입니다.
    case fileCoordinationFailed(description: String, underlyingError: Error? = nil)
    
    // MARK: - Migration Errors
    /// 데이터 마이그레이션 과정에서 모든 버전의 디코딩에 실패했을 때 발생하는 오류입니다.
    case migrationFailed(key: String, underlyingErrors: [Error])
    
    // MARK: - Equatable Conformance
    
    /// - 두 에러가 모두 `nil`이거나, 모두 `nil`이 아닌 경우 (즉, 에러의 존재 유무가 같은 경우) `true`를 반환합니다.
    /// - 실제 에러 객체의 내용을 비교하지는 않습니다.
    private static func _areOptionalErrorsEqualByPresence(_ err1: Error?, _ err2: Error?) -> Bool {
        return (err1 == nil && err2 == nil) || (err1 != nil && err2 != nil)
    }
    
    public static func == (lhs: SwiftVaultError, rhs: SwiftVaultError) -> Bool {
        switch (lhs, rhs) {
        case let (.encodingFailed(type1, err1), .encodingFailed(type2, err2)):
            return type1 == type2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.decodingFailed(key1, type1, err1), .decodingFailed(key2, type2, err2)):
            return key1 == key2 && type1 == type2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.readFailed(key1, err1), .readFailed(key2, err2)):
            return key1 == key2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.writeFailed(key1, err1), .writeFailed(key2, err2)):
            return key1 == key2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.deleteFailed(key1, err1), .deleteFailed(key2, err2)):
            return key1 == key2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.clearAllFailed(err1), .clearAllFailed(err2)):
            return _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.initializationFailed(s1), .initializationFailed(s2)):
            return s1 == s2
        case let (.unsupportedOperation(desc1), .unsupportedOperation(desc2)):
            return desc1 == desc2
        case let (.backendError(reason1, err1), .backendError(reason2, err2)):
            return reason1 == reason2 && _areOptionalErrorsEqualByPresence(err1, err2)
            // FileManagerError 통합 케이스
        case let (.couldNotCreateDirectory(p1, e1), .couldNotCreateDirectory(p2, e2)):
            return p1 == p2 && _areOptionalErrorsEqualByPresence(e1, e2)
        case let (.couldNotSaveFile(p1, e1), .couldNotSaveFile(p2, e2)):
            return p1 == p2 && _areOptionalErrorsEqualByPresence(e1, e2)
        case let (.couldNotReadFile(p1, e1), .couldNotReadFile(p2, e2)):
            return p1 == p2 && _areOptionalErrorsEqualByPresence(e1, e2)
        case let (.couldNotDeleteFile(p1, e1), .couldNotDeleteFile(p2, e2)):
            return p1 == p2 && _areOptionalErrorsEqualByPresence(e1, e2)
        case let (.fileDoesNotExist(p1), .fileDoesNotExist(p2)):
            return p1 == p2
        case let (.couldNotLocateSystemDirectory(d1), .couldNotLocateSystemDirectory(d2)):
            return d1 == d2
        case let (.directoryListingFailed(p1, e1), .directoryListingFailed(p2, e2)):
            return p1 == p2 && _areOptionalErrorsEqualByPresence(e1, e2)
            // 동기화 및 마이그레이션 오류
        case let (.appGroupContainerUnavailable(id1, err1), .appGroupContainerUnavailable(id2, err2)):
            return id1 == id2 && _areOptionalErrorsEqualByPresence(err1, err2)
        case let (.fileCoordinationFailed(desc1, err1), .fileCoordinationFailed(desc2, err2)):
            return desc1 == desc2 && _areOptionalErrorsEqualByPresence(err1, err2)
        default:
            return false
        }
    }
}

extension SwiftVaultError {
    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let type, _): return "SwiftVaultError: Encoding failed for type \(type)."
        case .decodingFailed(let key, let type, _): return "SwiftVaultError: Decoding failed for key '\(key)', type \(type)."
        case .readFailed(let key, _): return "SwiftVaultError: Read failed for key '\(key)'."
        case .writeFailed(let key, _): return "SwiftVaultError: Write failed for key '\(key)'."
        case .deleteFailed(let key, _): return "SwiftVaultError: Delete failed for key '\(key)'."
        case .clearAllFailed(_): return "SwiftVaultError: Clear all failed."
        case .initializationFailed(let message): return "SwiftVaultError: Initialization failed - \(message)."
        case .unsupportedOperation(let description): return "SwiftVaultError: Unsupported operation - \(description)."
        case .backendError(let reason, _): return "SwiftVaultError: Backend error - \(reason)."
        case .couldNotCreateDirectory(let path, _): return "SwiftVaultError: Could not create directory at \(path)."
        case .couldNotSaveFile(let path, _): return "SwiftVaultError: Could not save file at \(path)."
        case .couldNotReadFile(let path, _): return "SwiftVaultError: Could not read file at \(path)."
        case .couldNotDeleteFile(let path, _): return "SwiftVaultError: Could not delete file at \(path)."
        case .fileDoesNotExist(let path): return "SwiftVaultError: File does not exist at \(path)."
        case .couldNotLocateSystemDirectory(let directoryName): return "SwiftVaultError: Could not locate system directory: \(directoryName)."
        case .directoryListingFailed(let path, _): return "SwiftVaultError: Failed to list contents of directory at \(path)."
        case .appGroupContainerUnavailable(let appGroupId, _): return "SwiftVaultError: App Group container unavailable for ID \(appGroupId)."
        case .fileCoordinationFailed(let description, _): return "SwiftVaultError: File coordination failed - \(description)."
        case .migrationFailed(let key, _): return "SwiftVaultError: Migration failed for key '\(key)'."
        }
    }
}
