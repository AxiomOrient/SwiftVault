import Foundation
import Combine
import OSLog

/// 파일 시스템을 백엔드로 사용하며, `NSFileCoordinator`를 통해 프로세스 간의 안전한 데이터 접근을 보장하는 `PersistenceService` 구현체입니다.
public actor SwiftVaultFileSystemService: SwiftVaultService {

    // MARK: - Public Properties

    public nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> {
        return changeStream
    }

    // MARK: - Private Properties

    private let baseDirectoryPath: FileManager.Path
    private let logger: Logger
    private let serviceName: String = "SwiftVaultFileSystemService"

    /// StoredObject 래퍼를 인코딩/디코딩하기 위한 내부 전용 직렬화 도구입니다.
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private let fileCoordinator: NSFileCoordinator
    private let (changeStream, changeContinuation): (AsyncStream<(key: String?, transactionID: UUID?)>, AsyncStream<(key: String?, transactionID: UUID?)>.Continuation)
    private var directoryObserver: FilePresenterObserver?

    // MARK: - Initialization

    public init(
        baseDirectory: FileManager.Path,
        loggerSubsystem: String = SwiftVault.Config.defaultLoggerSubsystem
    ) throws {
        self.baseDirectoryPath = baseDirectory
        self.logger = Logger(subsystem: loggerSubsystem, category: serviceName)
        self.fileCoordinator = NSFileCoordinator()

        (self.changeStream, self.changeContinuation) = AsyncStream<(key: String?, transactionID: UUID?)>.makeStream()

        do {
            try baseDirectory.createDirectoryIfNeeded()
            let baseURL = try baseDirectory.url()
            self.logger.info("Initialized. Base directory: \(baseURL.path, privacy: .public)")
        } catch {
            let errorDescription = "Failed to create base directory during initialization: \(error.localizedDescription)"
            if let svError = error as? SwiftVaultError {
                self.logger.error("Failed to initialize FileSystem-based service. Error: \(svError.localizedDescription, privacy: .public)")
            } else {
                self.logger.error("An unexpected error occurred during FileSystem-based service initialization: \(error.localizedDescription, privacy: .public)")
            }
            throw SwiftVaultError.initializationFailed(errorDescription)
        }

        Task {
            await self.initializeObserver()
        }
    }

    deinit {
        changeContinuation.finish()
        logger.debug("Deinitialized and finished stream. Directory observer will be cleaned up by ARC.")
    }

    // MARK: - PersistenceService Implementation

    public func remove(forKey key: String) async throws {
        let path = try filePath(forKey: key)
        let targetURL = try path.url()
        logger.debug("Attempting to remove file for key '\(key)' at path '\(targetURL.path, privacy: .public)'")

        var fileCoordinationError: NSError?
        var deleteError: Error?

        fileCoordinator.coordinate(writingItemAt: targetURL, options: .forDeleting, error: &fileCoordinationError) { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.info("Attempted to remove non-existent file '\(url.path, privacy: .public)'. No action taken.")
                return
            }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                deleteError = error
            }
        }

        if let error = fileCoordinationError {
            throw SwiftVaultError.fileCoordinationFailed(description: "Remove operation coordination failed.", underlyingError: error)
        }
        if let error = deleteError {
            throw SwiftVaultError.deleteFailed(key: key, underlyingError: error)
        }

        logger.info("Successfully removed file for key '\(key, privacy: .public)' (or file did not exist).")
        // 삭제 작업은 특정 트랜잭션 ID가 없으므로 nil을 전달합니다.
        changeContinuation.yield((key: key, transactionID: nil))
    }

    public func exists(forKey key: String) async -> Bool {
        do {
            let path = try filePath(forKey: key)
            let url = try path.url()
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            // 경로 생성 실패는 예상치 못한 오류일 가능성이 높으므로 Error 레벨로 로깅합니다.
            logger.error("Could not check existence for key '\(key)' because path generation failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func clearAll() async throws {
        let baseURL = try baseDirectoryPath.url()
        logger.warning("Attempting to clear all data from directory '\(baseURL.path, privacy: .public)'")

        guard FileManager.default.fileExists(atPath: baseURL.path) else {
            logger.info("Base directory '\(baseURL.path, privacy: .public)' does not exist. No action needed for clearAll.")
            return
        }

        let fileURLs: [URL]
        do {
            fileURLs = try FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil, options: [])
        } catch {
            throw SwiftVaultError.clearAllFailed(underlyingError: error)
        }

        if fileURLs.isEmpty {
            logger.info("Base directory is empty. No action needed for clearAll. Path: \(baseURL.path, privacy: .public)")
            return
        }

        var fileCoordinationError: NSError?
        var batchDeleteError: Error?

        fileCoordinator.coordinate(writingItemAt: baseURL, options: .forDeleting, error: &fileCoordinationError) { directoryURL in
            do {
                let currentFileURLs = try FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: [])
                for fileURL in currentFileURLs {
                    try FileManager.default.removeItem(at: fileURL)
                }
            } catch {
                batchDeleteError = error
            }
        }

        if let error = fileCoordinationError {
            throw SwiftVaultError.fileCoordinationFailed(description: "clearAll operation coordination failed.", underlyingError: error)
        }
        if let error = batchDeleteError {
            throw SwiftVaultError.clearAllFailed(underlyingError: error)
        }

        logger.info("Successfully cleared all data from directory '\(baseURL.path, privacy: .public)'")
        // 전체 삭제는 특정 키/ID가 없으므로 (nil, nil) 전달
        changeContinuation.yield((key: nil, transactionID: nil))
    }

    // MARK: - Raw Data Handling

    public func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws {
        let path = try filePath(forKey: key)
        let targetURL = try path.url()
        logger.debug("Attempting to save raw data to file '\(targetURL.path)' with transaction \(transactionID.uuidString.prefix(8))")

        let objectToStore = StoredObject(value: data, transactionID: transactionID)
        let dataToSave: Data
        do {
            dataToSave = try encoder.encode(objectToStore)
        } catch {
            throw SwiftVaultError.encodingFailed(type: "StoredObject", underlyingError: error)
        }

        var fileCoordinationError: NSError?
        var writeError: Error?

        fileCoordinator.coordinate(writingItemAt: targetURL, options: .forReplacing, error: &fileCoordinationError) { url in
            do {
                try dataToSave.write(to: url, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = fileCoordinationError {
            throw SwiftVaultError.fileCoordinationFailed(description: "Save raw data coordination failed.", underlyingError: error)
        }
        if let error = writeError {
            throw SwiftVaultError.writeFailed(key: key, underlyingError: error)
        }

        logger.info("Successfully saved raw data to file '\(targetURL.path, privacy: .public)'")
        // 직접 수행한 변경이므로 트랜잭션 ID를 함께 전달
        changeContinuation.yield((key: key, transactionID: transactionID))
    }

    public func loadData(forKey key: String) async throws -> Data? {
        let path = try filePath(forKey: key)
        let targetURL = try path.url()
        logger.debug("Attempting to load raw data from file '\(targetURL.path, privacy: .public)'")

        var loadedRawData: Data?
        var fileCoordinationError: NSError?
        var readError: Error?

        fileCoordinator.coordinate(readingItemAt: targetURL, options: [], error: &fileCoordinationError) { url in
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                loadedRawData = try Data(contentsOf: url)
            } catch {
                readError = error
            }
        }

        if let error = fileCoordinationError {
            throw SwiftVaultError.fileCoordinationFailed(description: "Load raw data coordination failed.", underlyingError: error)
        }
        if let error = readError {
            throw SwiftVaultError.readFailed(key: key, underlyingError: error)
        }

        guard let encodedObject = loadedRawData else { return nil }

        do {
            let storedObject = try decoder.decode(StoredObject.self, from: encodedObject)
            return storedObject.value
        } catch {
            logger.warning("Could not decode StoredObject for key '\(key)'. Data might be in an old format or corrupted. Returning nil. Error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Helper Methods

    private func filePath(forKey key: String) throws -> FileManager.Path {
        let baseURL = try baseDirectoryPath.url()
        let fileURL = baseURL.appendingPathComponent(key, isDirectory: false)
        return .url(fileURL)
    }

    private func initializeObserver() async {
        do {
            let baseURL = try self.baseDirectoryPath.url()
            guard baseURL.isFileURL else {
                logger.error("Cannot initialize FilePresenterObserver with a non-file URL: \(baseURL.absoluteString, privacy: .public)")
                return
            }

            self.directoryObserver = FilePresenterObserver(fileURL: baseURL) { [weak self] change in
                guard let self else { return }
                Task {
                    await self.processFileChange(change)
                }
            }
            self.directoryObserver?.startObserving()
            logger.debug("FilePresenterObserver initialized and started observing directory: \(baseURL.path, privacy: .public)")
        } catch {
            logger.error("Failed to get URL for observer initialization. Observer will not be started. Error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func processFileChange(_ change: FilePresenterObserver.Change) {
        let key: String
        let url: URL

        switch change {
        case .modified(let u):
            key = u.lastPathComponent
            url = u
        case .deleted(let u):
            key = u.lastPathComponent
            // 삭제된 파일은 내용을 읽을 수 없으므로 transactionID는 nil입니다.
            changeContinuation.yield((key: key, transactionID: nil))
            return
        case .moved(let fromURL, let toURL):
            // 이동된 경우, 이전 키는 삭제된 것으로 간주하고(ID=nil), 새 키는 수정된 것으로 간주합니다.
            let oldKey = fromURL.lastPathComponent
            changeContinuation.yield((key: oldKey, transactionID: nil))
            key = toURL.lastPathComponent
            url = toURL
        }

        let transactionID: UUID?
        do {
            let fileData = try Data(contentsOf: url)
            let storedObject = try decoder.decode(StoredObject.self, from: fileData)
            transactionID = storedObject.transactionID
        } catch {
            // 파일을 읽을 수 없거나 디코딩에 실패하면 ID를 알 수 없습니다.
            // 외부 변경 감지 시 파일 상태가 일시적으로 불안정할 수 있으므로 오류를 로깅하고 transactionID는 nil로 처리합니다.
            logger.warning("Could not read or decode StoredObject from file '\(url.path, privacy: .public)' during external change processing. Transaction ID will be nil. Error: \(error.localizedDescription)")
            transactionID = nil
        }

        changeContinuation.yield((key: key, transactionID: transactionID))
    }
}
