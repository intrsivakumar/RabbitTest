
import Foundation
import UserNotifications
import UIKit

class PushTokenManager {
    
    private let storageHelper: StorageHelper
    private let networkHandler: NetworkHandler
    private let eventTracker: ManualEventTracker
    
    private var currentAPNSToken: String?
    private var currentFCMToken: String?
    
    init(storageHelper: StorageHelper = StorageHelper(),
         networkHandler: NetworkHandler = NetworkHandler(),
         eventTracker: ManualEventTracker = ManualEventTracker()) {
        self.storageHelper = storageHelper
        self.networkHandler = networkHandler
        self.eventTracker = eventTracker
        
        loadStoredTokens()
    }
    
    // MARK: - Public Methods
    
    func registerPushToken(_ token: String, provider: PushProvider) {
        let previousToken: String?
        
        switch provider {
        case .apns:
            previousToken = currentAPNSToken
            currentAPNSToken = token
            storageHelper.setValue(token, forKey: Constants.Storage.pushTokenAPNS)
        case .fcm:
            previousToken = currentFCMToken
            currentFCMToken = token
            storageHelper.setValue(token, forKey: Constants.Storage.pushTokenFCM)
        }
        
        // Only sync if token changed
        if previousToken != token {
            syncPushToken(provider)
            trackTokenUpdate(provider, token: token, previousToken: previousToken)
        }
        
        Logger.info("\(provider.rawValue) token registered: \(token.prefix(10))...")
    }
    
    func getPushToken(provider: PushProvider) -> String? {
        switch provider {
        case .apns:
            return currentAPNSToken
        case .fcm:
            return currentFCMToken
        }
    }
    
    func syncPushToken(_ provider: PushProvider) {
        guard let token = getPushToken(provider: provider) else {
            Logger.warning("No token to sync for provider: \(provider)")
            return
        }
        
        var tokenData: [String: Any] = [
            "token": token,
            "provider": provider == .apns ? "apns" : "fcm",
            "device_id": StorageHelper.getDeviceId(),
            "app_version": DeviceInfoCollector().getAppVersion(),
            "platform": DeviceInfoCollector().getDevicePlatform(),
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Add session ID if available
        if let sessionId = SessionManager.shared.getCurrentSessionId() {
            tokenData["session_id"] = sessionId
        }
        
        // Add permission status
        getNotificationPermissionStatus { permissionStatus in
            var updatedTokenData = tokenData
            updatedTokenData["permission_status"] = permissionStatus
            
            self.networkHandler.syncPushToken(updatedTokenData) { result in
                switch result {
                case .success:
                    Logger.info("\(provider) token synced successfully")
                    self.trackTokenSync(provider, success: true)
                case .failure(let error):
                    Logger.error("Failed to sync \(provider) token: \(error)")
                    self.trackTokenSync(provider, success: false, error: error)
                    
                    // Retry with exponential backoff
                    self.scheduleTokenRetry(provider, attempt: 1)
                }
            }
        }
    }
    
    func invalidatePushToken(_ provider: PushProvider) {
        let tokenToInvalidate = getPushToken(provider: provider)
        
        switch provider {
        case .apns:
            currentAPNSToken = nil
            storageHelper.removeValue(forKey: Constants.Storage.pushTokenAPNS)
        case .fcm:
            currentFCMToken = nil
            storageHelper.removeValue(forKey: Constants.Storage.pushTokenFCM)
        }
        
        // Notify server of token invalidation
        if let token = tokenToInvalidate {
            let invalidationData: [String: Any] = [
                "token": token,
                "provider": provider == .apns ? "apns" : "fcm",
                "device_id": StorageHelper.getDeviceId(),
                "action": "invalidate",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            
            networkHandler.invalidatePushToken(invalidationData) { result in
                switch result {
                case .success:
                    Logger.info("\(provider) token invalidated successfully")
                case .failure(let error):
                    Logger.error("Failed to invalidate \(provider) token: \(error)")
                }
            }
        }
        
        trackTokenInvalidation(provider)
        Logger.info("\(provider) token invalidated")
    }
    
    func refreshAllTokens() {
        // Request new APNS token
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        
        // FCM token refresh would be handled by Firebase SDK if integrated
        // For now, we'll just sync existing tokens
        if currentFCMToken != nil {
            syncPushToken(.fcm)
        }
    }
    
    // MARK: - Private Methods
    
    private func loadStoredTokens() {
        currentAPNSToken = storageHelper.getValue(forKey: Constants.Storage.pushTokenAPNS) as? String
        currentFCMToken = storageHelper.getValue(forKey: Constants.Storage.pushTokenFCM) as? String
    }
    
    private func getNotificationPermissionStatus(completion: @escaping (String) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status: String
            switch settings.authorizationStatus {
            case .authorized:
                status = "authorized"
            case .denied:
                status = "denied"
            case .notDetermined:
                status = "not_determined"
            case .provisional:
                status = "provisional"
            case .ephemeral:
                status = "ephemeral"
            @unknown default:
                status = "unknown"
            }
            completion(status)
        }
    }
    
    private func scheduleTokenRetry(_ provider: PushProvider, attempt: Int) {
        let maxAttempts = 3
        guard attempt <= maxAttempts else {
            Logger.error("Max token sync attempts reached for \(provider)")
            return
        }
        
        let delay = min(pow(2.0, Double(attempt)), 60.0) // Exponential backoff, max 60s
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Logger.info("Retrying token sync for \(provider) (attempt \(attempt)/\(maxAttempts))")
            self.syncPushToken(provider)
        }
    }
    
    private func trackTokenUpdate(_ provider: PushProvider, token: String, previousToken: String?) {
        let updateData: [String: Any] = [
            "provider": provider == .apns ? "apns" : "fcm",
            "token_changed": previousToken != nil,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "push_token_updated", data: updateData)
    }
    
    private func trackTokenSync(_ provider: PushProvider, success: Bool, error: Error? = nil) {
        var syncData: [String: Any] = [
            "provider": provider == .apns ? "apns" : "fcm",
            "success": success,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        if let error = error {
            syncData["error"] = error.localizedDescription
        }
        
        eventTracker.trackEvent(name: "push_token_sync", data: syncData)
    }
    
    private func trackTokenInvalidation(_ provider: PushProvider) {
        let invalidationData: [String: Any] = [
            "provider": provider == .apns ? "apns" : "fcm",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "push_token_invalidated", data: invalidationData)
    }
}
