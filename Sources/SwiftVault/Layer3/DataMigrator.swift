import Foundation
import OSLog

public typealias AnyCodable = Codable & Sendable

fileprivate typealias MigrationTask = @Sendable (any AnyCodable) throws -> any AnyCodable
fileprivate typealias DecodingTask = @Sendable (JSONDecoder, Data) -> (any AnyCodable)?

/// 데이터 마이그레이션 경로를 구성하고 실행하는 불변 객체입니다.
public struct DataMigrator<TargetModel: AnyCodable & Equatable>: Sendable {
    
    public final class Builder {
        private var paths: [ObjectIdentifier: (Any.Type, MigrationTask)] = [:]
        private var decodingTasks: [DecodingTask] = []
        private let targetType: TargetModel.Type
        
        public init(targetType: TargetModel.Type) {
            self.targetType = targetType
        }
        
        @discardableResult
        public func register<From: AnyCodable, To: AnyCodable>(
            from: From.Type,
            to: To.Type,
            converter: @escaping @Sendable (From) -> To
        ) -> Self {
            let fromID = ObjectIdentifier(from)
            paths[fromID] = (to, { anyValue in
                guard let value = anyValue as? From else { throw MigrationError.internalTypeMismatch }
                return converter(value)
            })
            decodingTasks.append({ decoder, data in try? decoder.decode(From.self, from: data) })
            return self
        }
        
        public func build() -> DataMigrator {
            return DataMigrator(targetType: self.targetType, paths: self.paths, decodingTasks: self.decodingTasks)
        }
    }
    
    private let targetType: TargetModel.Type
    private let paths: [ObjectIdentifier: (Any.Type, MigrationTask)]
    private let decodingTasks: [DecodingTask]
    private let logger: Logger
    
    fileprivate init(targetType: TargetModel.Type, paths: [ObjectIdentifier: (Any.Type, MigrationTask)], decodingTasks: [DecodingTask]) {
        self.targetType = targetType
        self.paths = paths
        self.decodingTasks = decodingTasks
        self.logger = Logger(subsystem: SwiftVault.Config.defaultLoggerSubsystem, category: "DataMigrator")
    }

    /// 주어진 데이터를 최신 버전으로 마이그레이션합니다.
    /// 이 메서드는 이제 데이터를 직접 저장하지 않고, 변환된 데이터만 반환합니다.
    func migrate(data: Data) async throws -> (data: Data, wasMigrated: Bool) {
        let decoder = JSONDecoder()
        
        if (try? decoder.decode(TargetModel.self, from: data)) != nil {
            return (data, false) // 이미 최신 버전, 마이그레이션 불필요
        }
        
        var currentModel: (any AnyCodable)?
        for task in decodingTasks {
            if let model = task(decoder, data) {
                currentModel = model
                break
            }
        }
        
        guard let initialModel = currentModel else {
            throw MigrationError.decodingFailed
        }
        
        logger.info("Detected old data version. Starting migration chain...")
        
        var modelToMigrate = initialModel
        var currentTypeID = ObjectIdentifier(type(of: modelToMigrate))

        while currentTypeID != ObjectIdentifier(targetType) {
            guard let (nextType, task) = paths[currentTypeID] else {
                throw MigrationError.pathNotFound(from: String(describing: type(of: modelToMigrate)))
            }
            
            modelToMigrate = try task(modelToMigrate)
            currentTypeID = ObjectIdentifier(nextType)
        }

        // 버그 수정: 최종 모델을 안전하게 캐스팅하고 인코딩합니다.
        guard let finalModel = modelToMigrate as? TargetModel else {
            throw MigrationError.finalTypeMismatch
        }
        
        let finalData = try JSONEncoder().encode(finalModel)
        return (finalData, true)
    }
}

fileprivate enum MigrationError: Error, LocalizedError {
    case internalTypeMismatch
    case decodingFailed
    case pathNotFound(from: String)
    case finalTypeMismatch
    
    var errorDescription: String? {
        switch self {
        case .internalTypeMismatch: "Internal error: Migration type mismatch."
        case .decodingFailed: "Failed to decode data into any known version."
        case .pathNotFound(let from): "Migration path from \(from) not found. The migration chain is broken."
        case .finalTypeMismatch: "The final migrated object does not match the target type."
        }
    }
}
