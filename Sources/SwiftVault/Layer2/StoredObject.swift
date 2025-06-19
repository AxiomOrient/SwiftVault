import Foundation

/// 데이터와 트랜잭션 ID를 함께 저장하기 위한 공유 래퍼 타입입니다.
struct StoredObject: Codable {
    let value: Data
    let transactionID: UUID
}
