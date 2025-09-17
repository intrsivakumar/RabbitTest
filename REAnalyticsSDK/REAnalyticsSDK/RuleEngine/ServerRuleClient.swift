
import Foundation

class ServerRuleClient {
    
    private let networkHandler: NetworkHandler
    private let localRuleEngine: LocalRuleEngine
    private let storageHelper: StorageHelper
    
    private var syncTimer: Timer?
    private let syncInterval: TimeInterval = 3600 // 1 hour
    
    init(networkHandler: NetworkHandler = NetworkHandler(),
         localRuleEngine: LocalRuleEngine = LocalRuleEngine(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.networkHandler = networkHandler
        self.localRuleEngine = localRuleEngine
        self.storageHelper = storageHelper
        
        setupPeriodicSync()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func syncRules() {
        fetchRulesFromServer { [weak self] result in
            switch result {
            case .success(let rules):
                self?.localRuleEngine.updateRules(rules)
                self?.saveLastSyncTime()
                Logger.info("Successfully synced \(rules.count) rules from server")
            case .failure(let error):
                Logger.error("Failed to sync rules from server: \(error)")
            }
        }
    }
    
    func evaluateServerRule(_ eventData: [String: Any], completion: @escaping (Result<[Action], Error>) -> Void) {
        networkHandler.sendRuleEvaluation(eventData) { result in
            switch result {
            case .success(let response):
                if let actions = self.parseActionsFromResponse(response) {
                    completion(.success(actions))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func reportRuleExecution(_ ruleId: String, success: Bool, context: [String: Any]) {
        let executionData: [String: Any] = [
            "rule_id": ruleId,
            "success": success,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "context": context
        ]
        
        networkHandler.sendRuleExecutionReport(executionData) { result in
            switch result {
            case .success:
                Logger.debug("Rule execution reported successfully")
            case .failure(let error):
                Logger.error("Failed to report rule execution: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            self?.syncRules()
        }
        
        // Initial sync
        syncRules()
    }
    
    private func fetchRulesFromServer(completion: @escaping (Result<[Rule], Error>) -> Void) {
        let lastSyncTime = getLastSyncTime()
        let parameters: [String: Any] = [
            "last_sync": lastSyncTime?.timeIntervalSince1970 ?? 0,
            "device_id": StorageHelper.getDeviceId(),
            "app_version": DeviceInfoCollector().getAppVersion()
        ]
        
        networkHandler.fetchRules(parameters) { result in
            switch result {
            case .success(let data):
                do {
                    let response = try JSONDecoder().decode(RulesResponse.self, from: data)
                    completion(.success(response.rules))
                } catch {
                    completion(.failure(error))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func parseActionsFromResponse(_ response: Data) -> [Action]? {
        do {
            let actionResponse = try JSONDecoder().decode(ActionResponse.self, from: response)
            return actionResponse.actions
        } catch {
            Logger.error("Failed to parse actions from server response: \(error)")
            return nil
        }
    }
    
    private func getLastSyncTime() -> Date? {
        return storageHelper.getValue(forKey: "rules_last_sync_time") as? Date
    }
    
    private func saveLastSyncTime() {
        storageHelper.setValue(Date(), forKey: "rules_last_sync_time")
    }
}

// MARK: - Response Models

private struct RulesResponse: Codable {
    let rules: [Rule]
    let version: String
    let timestamp: Date
}

private struct ActionResponse: Codable {
    let actions: [Action]
    let requestId: String
}
