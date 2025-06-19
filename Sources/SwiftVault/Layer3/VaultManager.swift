import Foundation

/// SwiftVault의 모든 데이터 컨트롤러와 서비스를 중앙에서 관리하는 싱글턴 액터입니다.
@MainActor
internal final class VaultManager {
    static let shared = VaultManager()
    
    private var storageCache: [String: Any] = [:]
    private var serviceCache: [SwiftVaultStorageType: SwiftVaultService] = [:]
    
    private init() {}
    
    /// 지정된 데이터 정의에 맞는 공유 `VaultDataStorage` 인스턴스를 반환합니다.
    func storage<S: VaultStorable>(for definition: S.Type) -> VaultDataStorage<S.Value> {
        let key = definition.key
        if let existingStorage = storageCache[key] as? VaultDataStorage<S.Value> {
            return existingStorage
        }
        
        let service = getOrCreateService(for: definition.storageType)
        
        let builder = DataMigrator.Builder(targetType: S.Value.self)
        definition.configure(builder: builder)
        let migrator = builder.build()
        
        let newStorage = VaultDataStorage<S.Value>(
            key: key,
            defaultValue: definition.defaultValue,
            service: service,
            migrator: migrator,
            encoder: definition.encoder,
            decoder: definition.decoder
        )
        storageCache[key] = newStorage
        return newStorage
    }
    
    /// 지정된 저장소 타입에 맞는 공유 `SwiftVaultService` 인스턴스를 반환합니다.
    private func getOrCreateService(for storageType: SwiftVaultStorageType) -> SwiftVaultService {
        // 이 메서드는 storage(for:) 내부에서만 호출되며,
        // storage(for:)가 이미 @MainActor에 의해 보호되므로 이 메서드 또한 안전합니다.
        if let cachedService = serviceCache[storageType] {
            return cachedService
        }
        
        do {
            let newService = try storageType.makeService()
            serviceCache[storageType] = newService
            return newService
        } catch {
            fatalErrorOnSetupFailure(error, key: "ServiceCreation", storageTypeDescription: String(describing: storageType))
        }
    }
}
