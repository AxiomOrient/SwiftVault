import Foundation

public protocol SwiftVaultService: Sendable {
    
    /// 지정된 키에 원시 데이터를 저장하고, 이 트랜잭션의 고유 ID를 함께 기록합니다.
    func saveData(_ data: Data, forKey key: String, transactionID: UUID) async throws
    
    /// 지정된 키에서 원시 데이터를 로드합니다.
    func loadData(forKey key: String) async throws -> Data?
    
    /// 지정된 키의 값을 삭제합니다.
    func remove(forKey key: String) async throws
    
    /// 지정된 키에 값이 존재하는지 확인합니다.
    func exists(forKey key: String) async -> Bool
    
    /// 이 서비스가 관리하는 모든 데이터를 삭제합니다.
    func clearAll() async throws
    
    /// 외부 소스에 의한 데이터 변경을 알리는 비동기 스트림입니다.
    nonisolated var externalChanges: AsyncStream<(key: String?, transactionID: UUID?)> { get }
}
