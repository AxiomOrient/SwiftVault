import Testing
@testable import SwiftVault
import Foundation

/// `FilePresenterObserver`의 동작을 검증하는 테스트 스위트입니다.
/// 파일 시스템의 비동기적 특성으로 인한 테스트 간 간섭을 막기 위해 스위트 전체를 MainActor에서 직렬로 실행합니다.
@Suite("FilePresenterObserver Tests")
@MainActor
struct FilePresenterObserverTests {

    // MARK: - Test State Coordinator
    
    /// 테스트 중 발생하는 비동기 이벤트와 상태를 스레드에 안전하게 관리하는 액터입니다.
    private actor TestStateCoordinator {
        private(set) var receivedChanges: [FilePresenterObserver.Change] = []
        private let streamContinuation: AsyncStream<FilePresenterObserver.Change>.Continuation
        
        let changesStream: AsyncStream<FilePresenterObserver.Change>

        init() {
            let (stream, continuation) = AsyncStream.makeStream(of: FilePresenterObserver.Change.self)
            self.changesStream = stream
            self.streamContinuation = continuation
        }

        /// 변경 사항을 기록하고 스트림에 이벤트를 전달합니다.
        func recordChange(_ change: FilePresenterObserver.Change) {
            receivedChanges.append(change)
            streamContinuation.yield(change)
        }
    }

    // MARK: - Test Cases

    /// **Intent:** 유효하지 않은 URL(non-file URL)로 초기화 시도 시 `nil`이 반환되는지 검증합니다.
    @Test("Initialization with invalid URL returns nil")
    func testInitializationWithInvalidURLReturnsNil() throws {
        // Arrange
        let invalidURL = try #require(URL(string: "http://example.com"))

        // Act
        let observer = FilePresenterObserver(fileURL: invalidURL) { _ in }

        // Assert
        #expect(observer == nil)
    }

    /// **Intent:** 관찰 중인 디렉토리에 하위 파일이 추가되었을 때 `.modified` 이벤트를 수신하는지 검증합니다.
    @Test("Subitem addition event is received")
    func testSubitemAdditionEvent() async throws {
        // Arrange
        let testDir = try createTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: testDir) }

        let coordinator = TestStateCoordinator()
        let observer = try #require(FilePresenterObserver(fileURL: testDir) { change in
            Task { await coordinator.recordChange(change) }
        })

        let newFileURL = testDir.appendingPathComponent("newFile.txt")

        // Act
        observer.startObserving()
        defer { observer.stopObserving() }
        
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        FileManager.default.createFile(atPath: newFileURL.path, contents: "hello".data(using: .utf8))
        
        // Assert
        let eventFound = await waitForChange(from: coordinator) { change in
            if case .modified(let url) = change, url == newFileURL {
                return true
            }
            return false
        }
        #expect(eventFound, "A .modified event for the new file was not received.")
    }

    // MARK: - Private Helpers
    
    private func createTemporaryDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let dirURL = tempDir.appendingPathComponent("FilePresenterObserverTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
        return dirURL
    }
    
    /// 지정된 조건에 맞는 변경 이벤트가 수신될 때까지 대기하고, 성공 여부를 반환하는 헬퍼 함수입니다.
    private func waitForChange(
        from coordinator: TestStateCoordinator,
        timeout: TimeInterval = 2.0,
        predicate: @escaping @Sendable (FilePresenterObserver.Change) -> Bool
    ) async -> Bool {
        
        // TaskGroup을 사용하여 이벤트 대기와 타임아웃을 동시에 실행합니다.
        let result = await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            // 이벤트 대기 Task
            group.addTask {
                let initialChanges = await coordinator.receivedChanges
                if initialChanges.contains(where: predicate) {
                    return true
                }
                // 'await'을 프로퍼티 접근이 아닌, 'for-await' 루프 구문 자체의 일부로 올바르게 사용합니다.
                for await change in coordinator.changesStream {
                    if predicate(change) {
                        return true
                    }
                }
                // 스트림이 종료되면 여기까지 도달
                return false
            }
            
            // 타임아웃 Task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000)) // Convert seconds to nanoseconds
                return false // 타임아웃 발생 시 false 반환
            }
            
            // 먼저 완료되는 Task의 결과를 받습니다.
            let firstResult = await group.next() ?? false
            group.cancelAll() // 한 쪽이 완료되면 다른 Task는 취소
            return firstResult
        }
        
        return result
    }
}
