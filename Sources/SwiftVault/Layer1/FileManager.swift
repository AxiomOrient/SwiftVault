import Foundation
import OSLog

/// 파일 및 디렉토리 관련 작업을 수행하는 유틸리티 확장입니다.
public extension FileManager {
    
    /// 파일 및 디렉토리 경로를 나타내는 열거형입니다.
    /// Hashable을 준수하여 Dictionary의 키로 사용될 수 있습니다.
    enum Path: Sendable, Hashable {
        case document(String) // Documents Directory 내 경로
        case cache(String)    // Caches Directory 내 경로
        case applicationSupport(String)
        case custom(String)   // 전체 경로 (Absolute Path)
        case url(URL)         // 일반 URL (로컬 파일 또는 웹 URL)
        
        // Path 작업 전용 로거
        private static let logger = Logger(subsystem: "com.axiomorient.SwiftVault.Foundation", category: "FileManager.Path")
        
        /// 현재 경로의 URL을 반환합니다. 시스템 디렉토리 경로를 찾지 못하면 오류를 던집니다.
        public func url() throws -> URL {
            let fileManager = FileManager.default
            switch self {
            case .document(let path):
                guard let baseURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw SwiftVaultError.couldNotLocateSystemDirectory(directoryName: "Document")
                }
                return baseURL.appendingPathComponent(path)
            case .cache(let path):
                guard let baseURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    throw SwiftVaultError.couldNotLocateSystemDirectory(directoryName: "Cache")
                }
                return baseURL.appendingPathComponent(path)
            case .applicationSupport(let path):
                guard let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                    throw SwiftVaultError.couldNotLocateSystemDirectory(directoryName: "Application Support")
                }
                return baseURL.appendingPathComponent(path)
            case .custom(let path):
                return URL(fileURLWithPath: path)
            case .url(let url):
                return url
            }
        }
        
        /// 경로에서 마지막 컴포넌트 (파일명 또는 디렉토리명)를 반환합니다.
        public func fileName() throws -> String {
            return try self.url().lastPathComponent
        }
        
        /// 해당 경로가 가리키는 항목이 디렉토리인지 확인합니다.
        public func isDirectory() throws -> Bool {
            var isDir: ObjCBool = false
            let targetURL = try self.url()
            guard targetURL.isFileURL else { return false }
            return FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir) && isDir.boolValue
        }
        
        public func parentDirectoryURL() throws -> URL {
            return try self.url().deletingLastPathComponent()
        }
        
        /// 디렉토리가 존재하지 않으면 생성합니다. Web URL은 지원하지 않습니다.
        public func createDirectoryIfNeeded() throws {
            let targetURL = try self.url()
            guard targetURL.isFileURL else {
                let errorDescription = "Cannot create directory for non-file URL: \(targetURL.absoluteString)"
                Self.logger.error("Cannot create directory for non-file URL: \(targetURL.absoluteString, privacy: .public)")
                throw SwiftVaultError.unsupportedOperation(description: errorDescription)
            }
            
            let path = targetURL.path
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    Self.logger.debug("Directory already exists at \(path, privacy: .public)")
                    return
                } else {
                    let svError = SwiftVaultError.couldNotCreateDirectory(
                        path: path,
                        underlyingError: NSError(domain: NSPOSIXErrorDomain, code: Int(EEXIST), userInfo: [NSLocalizedDescriptionKey: "A file already exists at the specified path."])
                    )
                    Self.logger.error("Failed to create directory at \(path, privacy: .public). A file already exists at this path. Error: \(svError.localizedDescription, privacy: .public)")
                    throw svError
                }
            } else {
                do {
                    try fileManager.createDirectory(at: targetURL, withIntermediateDirectories: true, attributes: nil)
                    Self.logger.debug("Successfully created directory at \(path, privacy: .public)")
                } catch {
                    let svError = SwiftVaultError.couldNotCreateDirectory(path: path, underlyingError: error)
                    Self.logger.error("Failed to create directory at \(path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                    throw svError
                }
            }
        }
        
        /// 현재 경로의 부모 디렉토리가 존재하지 않으면 생성합니다.
        private func createParentDirectoryIfNeeded() throws {
            let targetURL = try self.url()
            guard targetURL.isFileURL, targetURL.path != "/" else {
                return
            }
            
            let parentDirURL = try self.parentDirectoryURL()
            try FileManager.Path.url(parentDirURL).createDirectoryIfNeeded()
        }
        
        /// 데이터를 파일로 저장합니다. 필요시 상위 디렉토리를 생성합니다. Web URL은 지원하지 않습니다.
        public func save(data: Data) throws {
            let targetURL = try self.url()
            guard targetURL.isFileURL else {
                let errorDescription = "Cannot save data to non-file URL: \(targetURL.absoluteString)"
                Self.logger.error("Cannot save data to non-file URL: \(targetURL.absoluteString, privacy: .public)")
                throw SwiftVaultError.unsupportedOperation(description: errorDescription)
            }
            
            do {
                try createParentDirectoryIfNeeded()
                try data.write(to: targetURL)
                Self.logger.debug("Successfully saved data to \(targetURL.path, privacy: .public)")
            } catch let error as SwiftVaultError {
                throw error
            } catch {
                let svError = SwiftVaultError.couldNotSaveFile(path: targetURL.path, underlyingError: error)
                Self.logger.error("Failed to save data to \(targetURL.path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                throw svError
            }
        }
        
        /// 파일에서 데이터를 읽습니다. 로컬 파일에 대해서만 동작합니다.
        public func read() throws -> Data {
            let targetURL = try self.url()
            guard targetURL.isFileURL else {
                let errorDescription = "Cannot read data directly from non-file URL: \(targetURL.absoluteString). Use URLSession for web content."
                Self.logger.error("Cannot read data directly from non-file URL: \(targetURL.absoluteString, privacy: .public). Use URLSession for web content.")
                throw SwiftVaultError.unsupportedOperation(description: errorDescription)
            }
            
            // ⭐️ [오류 수정] fileExists(at:) -> fileExists(atPath:)로 수정하고, 파라미터로 URL의 path를 전달합니다.
            guard FileManager.default.fileExists(atPath: targetURL.path) else {
                let svError = SwiftVaultError.fileDoesNotExist(path: targetURL.path)
                Self.logger.warning("Attempted to read non-existent file at \(targetURL.path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                throw svError
            }
            
            do {
                let data = try Data(contentsOf: targetURL)
                Self.logger.debug("Successfully read data from \(targetURL.path, privacy: .public)")
                return data
            } catch {
                let svError = SwiftVaultError.couldNotReadFile(path: targetURL.path, underlyingError: error)
                Self.logger.error("Failed to read data from \(targetURL.path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                throw svError
            }
        }
        
        /// 파일 또는 디렉토리를 삭제합니다. Web URL은 지원하지 않습니다.
        public func delete() throws {
            let targetURL = try self.url()
            guard targetURL.isFileURL else {
                let errorDescription = "Cannot delete non-file URL: \(targetURL.absoluteString)"
                Self.logger.error("Cannot delete non-file URL: \(targetURL.absoluteString, privacy: .public)")
                throw SwiftVaultError.unsupportedOperation(description: errorDescription)
            }
            
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: targetURL.path) else {
                let svError = SwiftVaultError.fileDoesNotExist(path: targetURL.path)
                Self.logger.warning("Attempted to delete non-existent item at \(targetURL.path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                throw svError
            }
            
            do {
                try fileManager.removeItem(at: targetURL)
                Self.logger.debug("Successfully deleted item at \(targetURL.path, privacy: .public)")
            } catch {
                let svError = SwiftVaultError.couldNotDeleteFile(path: targetURL.path, underlyingError: error)
                Self.logger.error("Failed to delete item at \(targetURL.path, privacy: .public): \(svError.localizedDescription, privacy: .public)")
                throw svError
            }
        }
    }
}

public extension FileManager {
    
    /// 주어진 URL의 파일 또는 디렉토리가 로컬 파일 시스템에 존재하는지 확인합니다. Web URL은 항상 false를 반환합니다.
    func fileExists(at url: URL) -> Bool {
        guard url.isFileURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    /// 앱의 주요 저장 디렉토리(Documents, Cache, Application Support)의 모든 내용을 삭제합니다.
    func clearApplicationDirectories() throws {
        let fileManager = FileManager.default
        let directoriesToClearContents: [FileManager.SearchPathDirectory] = [
            .documentDirectory,
            .cachesDirectory,
            .applicationSupportDirectory
        ]
        
        let logger: Logger = Logger(subsystem: "com.axiomorient.SwiftVault.Foundation", category: "FileManagerUtil")
        
        for directory: FileManager.SearchPathDirectory in directoriesToClearContents {
            guard let directoryURL = fileManager.urls(for: directory, in: .userDomainMask).first else {
                logger.warning("Could not locate URL for system directory: \(directory.description). Skipping.")
                throw SwiftVaultError.couldNotLocateSystemDirectory(directoryName: directory.description)
            }
            
            if directory == .applicationSupportDirectory && !fileManager.fileExists(atPath: directoryURL.path) {
                do {
                    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
                    logger.info("Created Application Support directory as it was missing: \(directoryURL.path)")
                } catch {
                    logger.warning("Failed to create missing Application Support directory \(directoryURL.path): \(error.localizedDescription). Skipping this directory.")
                    continue
                }
            }
            
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                
                guard !fileURLs.isEmpty else {
                    logger.info("Directory is already empty: \(directoryURL.lastPathComponent) (\(directory.description))")
                    continue
                }
                
                logger.info("Clearing contents of directory: \(directoryURL.lastPathComponent) (\(directory.description))...")
                for fileURL in fileURLs {
                    do {
                        try fileManager.removeItem(at: fileURL)
                    } catch {
                        logger.warning("Error clearing item \(fileURL.lastPathComponent) in \(directory.description): \(error.localizedDescription)")
                    }
                }
                logger.info("Finished clearing contents of directory: \(directoryURL.lastPathComponent) (\(directory.description))")
                
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                logger.info("Directory does not exist or is not accessible (normal if first run): \(directoryURL.path, privacy: .public)")
            } catch {
                logger.error("Failed to list contents of directory \(directoryURL.path): \(error.localizedDescription, privacy: .public)")
                throw SwiftVaultError.directoryListingFailed(path: directoryURL.path, underlyingError: error)
            }
        }
    }
}

extension FileManager.SearchPathDirectory: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .applicationDirectory: return "ApplicationDirectory"
        case .demoApplicationDirectory: return "DemoApplicationDirectory"
        case .developerApplicationDirectory: return "DeveloperApplicationDirectory"
        case .adminApplicationDirectory: return "AdminApplicationDirectory"
        case .libraryDirectory: return "LibraryDirectory"
        case .developerDirectory: return "DeveloperDirectory"
        case .userDirectory: return "UserDirectory"
        case .documentationDirectory: return "DocumentationDirectory"
        case .documentDirectory: return "DocumentDirectory"
        case .coreServiceDirectory: return "CoreServiceDirectory"
        case .autosavedInformationDirectory: return "AutosavedInformationDirectory"
        case .preferencePanesDirectory: return "PreferencePanesDirectory"
        case .applicationSupportDirectory: return "ApplicationSupportDirectory"
        case .desktopDirectory: return "DesktopDirectory"
        case .cachesDirectory: return "CachesDirectory"
        case .applicationScriptsDirectory: return "ApplicationScriptsDirectory"
        case .itemReplacementDirectory: return "ItemReplacementDirectory"
        case .allApplicationsDirectory: return "AllApplicationsDirectory"
        case .allLibrariesDirectory: return "AllLibrariesDirectory"
        case .trashDirectory: return "TrashDirectory"
        default: return "UnknownDirectory(\(self.rawValue))"
        }
    }
}
