import Foundation
import OSLog

/// `NSFilePresenter`를 사용하여 파일 또는 디렉토리의 변경 사항을 감지하는 클래스입니다.
///
/// 이 클래스는 지정된 URL(파일 또는 디렉토리)에 대한 관찰자로 시스템에 자신을 등록합니다.
/// 외부에서 해당 항목이 변경되면, 변경 유형과 대상 URL을 포함한 구체적인 정보를 `onChange` 클로저로 전달합니다.
final class FilePresenterObserver: NSObject, NSFilePresenter, @unchecked Sendable {
    
    // MARK: - Public Nested Types
    
    /// 파일 시스템에서 발생한 변경의 종류를 나타내는 열거형입니다.
    public enum Change: Sendable {
        /// 파일 내용이 수정되었거나, 디렉토리 내 항목이 추가/수정되었습니다.
        case modified(url: URL)
        /// 디렉토리 내 항목이 삭제되었습니다.
        case deleted(url: URL)
        /// 파일 또는 디렉토리의 위치가 변경되었습니다.
        case moved(from: URL, to: URL)
    }
    
    // MARK: - NSFilePresenter Protocol Requirements
    
    nonisolated let presentedItemURL: URL?
    nonisolated let presentedItemOperationQueue: OperationQueue
    
    // MARK: - Private Properties
    
    /// 파일 변경 시 호출될 클로저입니다. 변경에 대한 구체적인 정보를 담은 `Change` 타입을 전달합니다.
    private let onChange: @Sendable (Change) -> Void
    private let logger: Logger
    
    // MARK: - Initialization
    
    /// `FilePresenterObserver`의 새 인스턴스를 생성합니다.
    /// - Parameters:
    ///   - fileURL: 관찰할 로컬 파일 또는 디렉토리의 URL입니다.
    ///   - onChange: 변경 사항이 발생했을 때 실행할 클로저입니다.
    init?(fileURL: URL, onChange: @escaping @Sendable (Change) -> Void) {
        guard fileURL.isFileURL else {
            return nil
        }
        
        self.presentedItemURL = fileURL
        self.onChange = onChange
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.axiomorient.SwiftVault.FilePresenterObserverQueue"
        self.presentedItemOperationQueue = queue
        
        self.logger = Logger(subsystem: "com.axiomorient.SwiftVault.Foundation", category: "FilePresenterObserver")
        super.init()
    }
    
    deinit {
        stopObserving()
    }
    
    // MARK: - Public Methods
    
    /// 관찰을 시작합니다.
    public func startObserving() {
        guard let url = presentedItemURL else { return }
        NSFileCoordinator.addFilePresenter(self)
        
        if !FileManager.default.fileExists(atPath: url.path) {
            logger.warning("Started observing non-existent item: \(url.path, privacy: .public). Presenter registered, but no events will fire until item is created.")
        }
        logger.debug("Started observing: \(url.path)")
    }
    
    /// 관찰을 중지합니다.
    public func stopObserving() {
        NSFileCoordinator.removeFilePresenter(self)
        if let url = presentedItemURL {
            logger.debug("Stopped observing: \(url.path)")
        }
    }
    
    // MARK: - NSFilePresenter Protocol Methods
    
    /// 관찰 대상 자체(파일 또는 디렉토리)가 변경되었을 때 호출됩니다.
    nonisolated func presentedItemDidChange() {
        if let url = presentedItemURL {
            logger.debug("presentedItemDidChange: \(url.path)")
            onChange(.modified(url: url))
        }
    }
    
    /// 관찰 대상 디렉토리 내부의 항목이 변경(추가/수정)되었을 때 호출됩니다.
    nonisolated func presentedSubitemDidChange(at url: URL) {
        logger.debug("presentedSubitemDidChange: \(url.path)")
        onChange(.modified(url: url))
    }
    
    /// 관찰 대상 디렉토리 내부의 항목이 삭제될 것임을 알립니다.
    nonisolated func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        logger.debug("accommodatePresentedSubitemDeletion: \(url.path)")
        onChange(.deleted(url: url))
        completionHandler(nil)
    }
    
    /// 관찰 대상 디렉토리 내부의 항목이 이동했을 때 호출됩니다.
    nonisolated func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) {
        logger.debug("presentedSubitem didMove from \(oldURL.path) to \(newURL.path)")
        onChange(.moved(from: oldURL, to: newURL))
    }
}
