// Sources/SwiftVault/Layer1/ObserverTokenContainer.swift

import Foundation

/// NotificationCenter 관찰자 토큰을 스레드에 안전하게 관리하는 컨테이너 클래스입니다.
/// 이 클래스는 모듈 내에서 재사용되도록 internal로 선언되었습니다.
internal final class ObserverTokenContainer: @unchecked Sendable {
    private let lock = NSLock()
    private var token: (any NSObjectProtocol)?
    
    init(token: any NSObjectProtocol) {
        self.token = token
    }
    
    /// 토큰을 스레드 안전하게 한 번만 가져옵니다. 이후 컨테이너의 토큰은 nil이 됩니다.
    func take() -> (any NSObjectProtocol)? {
        lock.lock()
        defer { lock.unlock() }
        let takenToken = token
        token = nil
        return takenToken
    }
}
