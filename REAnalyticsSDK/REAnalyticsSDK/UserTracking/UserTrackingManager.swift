
import Foundation
import UIKit

class UserTrackingManager: NSObject {
    
    private let networkHandler: NetworkHandler
    private let storageHelper: StorageHelper
    private let encryptionHelper: EncryptionHelper
    private let consentManager: ConsentManager
    
    private var currentUserProfile: UserProfile?
    private var syncTimer: Timer?
    
    init(networkHandler: NetworkHandler = NetworkHandler(),
         storageHelper: StorageHelper = StorageHelper(),
         encryptionHelper: EncryptionHelper = EncryptionHelper(),
         consentManager: ConsentManager = ConsentManager.shared) {
        self.networkHandler = networkHandler
        self.storageHelper = storageHelper
        self.encryptionHelper = encryptionHelper
        self.consentManager = consentManager
        super.init()
        
        loadStoredUserProfile()
        setupPeriodicSync()
    }
    
    deinit {
        syncTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    func setUserDetails(_ user: UserProfile) {
        guard consentManager.hasConsent(for: .analytics) else {
            Logger.warning("User consent required for setting user details")
            return
        }
        
        // Validate user profile
        guard validateUserProfile(user) else {
            Logger.error("Invalid user profile provided")
            return
        }
        
        // Encrypt sensitive data
        var secureUser = user
        encryptSensitiveFields(&secureUser)
        
        // Store locally
        currentUserProfile = secureUser
        storeUserProfile(secureUser)
        
        // Sync with server
        syncUserProfile()
        
        Logger.info("User profile updated successfully")
    }
    
    func getUserDetails() -> UserProfile? {
        guard consentManager.hasConsent(for: .analytics) else {
            return nil
        }
        return currentUserProfile
    }
    
    func clearUserDetails() {
        currentUserProfile = nil
        storageHelper.removeValue(forKey: Constants.Storage.userProfile)
        
        // Notify server about user deletion
        if consentManager.hasConsent(for: .analytics) {
            deleteUserFromServer()
        }
        
        Logger.info("User profile cleared")
    }
    
    func syncUserProfile() {
        guard let userProfile = currentUserProfile,
              consentManager.hasConsent(for: .analytics) else {
            return
        }
        
        networkHandler.sendUserProfile(userProfile) { [weak self] result in
            switch result {
            case .success:
                Logger.info("User profile synced successfully")
            case .failure(let error):
                Logger.error("Failed to sync user profile: \(error)")
                self?.scheduleRetrySync()
            }
        }
    }
    
    func anonymizeUser() {
        guard var user = currentUserProfile else { return }
        
        // Anonymize sensitive fields
        user.email = nil
        user.phone = nil
        user.name = nil
        user.profilePhotoUrl = nil
        user.customAttributes = nil
        
        // Keep only non-identifiable data
        user.uniqueId = "anonymous_\(UUID().uuidString)"
        
        currentUserProfile = user
        storeUserProfile(user)
        
        Logger.info("User profile anonymized")
    }
    
    // MARK: - Private Methods
    
    private func loadStoredUserProfile() {
        guard let userData = storageHelper.getValue(forKey: Constants.Storage.userProfile) as? Data else {
            return
        }
        
        do {
            let userProfile = try JSONDecoder().decode(UserProfile.self, from: userData)
            currentUserProfile = userProfile
            decryptSensitiveFields(&currentUserProfile!)
        } catch {
            Logger.error("Failed to load stored user profile: \(error)")
            storageHelper.removeValue(forKey: Constants.Storage.userProfile)
        }
    }
    
    private func storeUserProfile(_ user: UserProfile) {
        do {
            let userData = try JSONEncoder().encode(user)
            storageHelper.setValue(userData, forKey: Constants.Storage.userProfile)
        } catch {
            Logger.error("Failed to store user profile: \(error)")
        }
    }
    
    private func validateUserProfile(_ user: UserProfile) -> Bool {
        // Validate required fields
        guard !user.uniqueId.isEmpty else {
            Logger.error("User uniqueId is required")
            return false
        }
        
        // Validate email format if provided
        if let email = user.email, !email.isEmpty {
            guard isValidEmail(email) else {
                Logger.error("Invalid email format")
                return false
            }
        }
        
        // Validate phone format if provided
        if let phone = user.phone, !phone.isEmpty {
            guard isValidPhoneNumber(phone) else {
                Logger.error("Invalid phone number format")
                return false
            }
        }
        
        return true
    }
    
    private func encryptSensitiveFields(_ user: inout UserProfile) {
        if let email = user.email {
            user.email = encryptionHelper.encrypt(string: email)
        }
        
        if let phone = user.phone {
            user.phone = encryptionHelper.encrypt(string: phone)
        }
        
        if let name = user.name {
            user.name = encryptionHelper.encrypt(string: name)
        }
    }
    
    private func decryptSensitiveFields(_ user: inout UserProfile) {
        if let email = user.email {
            user.email = encryptionHelper.decrypt(string: email)
        }
        
        if let phone = user.phone {
            user.phone = encryptionHelper.decrypt(string: phone)
        }
        
        if let name = user.name {
            user.name = encryptionHelper.decrypt(string: name)
        }
    }
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            self?.syncUserProfile()
        }
    }
    
    private func scheduleRetrySync() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.syncUserProfile()
        }
    }
    
    private func deleteUserFromServer() {
        // Implementation for GDPR/CCPA compliance
        // This would send a delete request to the server
        guard let userId = currentUserProfile?.uniqueId else { return }
        
        networkHandler.deleteUser(userId) { result in
            switch result {
            case .success:
                Logger.info("User deleted from server successfully")
            case .failure(let error):
                Logger.error("Failed to delete user from server: \(error)")
            }
        }
    }
    
    // MARK: - Validation Helpers
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegex = "^[+]?[0-9]{10,15}$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phonePredicate.evaluate(with: phone)
    }
}

// MARK: - Extensions

extension UserTrackingManager {
    
    func updateCustomAttribute(key: String, value: Any) {
        guard var user = currentUserProfile else { return }
        
        if user.customAttributes == nil {
            user.customAttributes = [:]
        }
        
        user.customAttributes?[key] = value
        setUserDetails(user)
    }
    
    func removeCustomAttribute(key: String) {
        guard var user = currentUserProfile else { return }
        
        user.customAttributes?.removeValue(forKey: key)
        setUserDetails(user)
    }
    
    func updatePreference(key: String, value: Any) {
        guard var user = currentUserProfile else { return }
        
        if user.preferences == nil {
            user.preferences = [:]
        }
        
        user.preferences?[key] = value
        setUserDetails(user)
    }
}
