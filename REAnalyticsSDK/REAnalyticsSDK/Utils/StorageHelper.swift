
import Foundation
import Security
import UIKit

class StorageHelper {
    
    private let keyService = "com.analytics.sdk.storage"
    private let userDefaults = UserDefaults.standard
    private let encryptionHelper = EncryptionHelper()
    
    // MARK: - Public Methods
    
    func setValue(_ value: Any, forKey key: String) {
        if isSecureKey(key) {
            storeSecurely(value, forKey: key)
        } else {
            userDefaults.set(value, forKey: key)
        }
    }
    
    func getValue(forKey key: String) -> Any? {
        if isSecureKey(key) {
            return getSecureValue(forKey: key)
        } else {
            return userDefaults.object(forKey: key)
        }
    }
    
    func removeValue(forKey key: String) {
        if isSecureKey(key) {
            removeSecureValue(forKey: key)
        } else {
            userDefaults.removeObject(forKey: key)
        }
    }
    
    func storeEncrypted(_ data: Data, forKey key: String) -> Bool {
        guard let encryptedData = encryptionHelper.encrypt(data: data) else {
            Logger.error("Failed to encrypt data for key: \(key)")
            return false
        }
        
        return storeInKeychain(encryptedData, forKey: key)
    }
    
    func getEncrypted(forKey key: String) -> Data? {
        guard let encryptedData = getFromKeychain(forKey: key) else {
            return nil
        }
        
        return encryptionHelper.decrypt(data: encryptedData)
    }
    
    // MARK: - Static Convenience Methods
    
    static func getAppId() -> String {
        return StorageHelper().getValue(forKey: Constants.Storage.appId) as? String ?? ""
    }
    
    static func getDeviceId() -> String {
        if let deviceId = StorageHelper().getValue(forKey: Constants.Storage.deviceId) as? String {
            return deviceId
        }
        
        // Generate and store new device ID
        let newDeviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        StorageHelper().setValue(newDeviceId, forKey: Constants.Storage.deviceId)
        return newDeviceId
    }
    
    static func getUserId() -> String? {
        return StorageHelper().getValue(forKey: Constants.Storage.userId) as? String
    }
    
    static func getAuthToken() -> String? {
        return StorageHelper().getValue(forKey: Constants.Storage.authToken) as? String
    }
    
    // MARK: - Private Methods
    
    private func isSecureKey(_ key: String) -> Bool {
        let secureKeys = [
            Constants.Storage.appId,
            Constants.Storage.authToken,
            Constants.Storage.userProfile,
            Constants.Storage.pushTokenAPNS,
            Constants.Storage.pushTokenFCM,
            Constants.Storage.resumeData
        ]
        
        return secureKeys.contains(key)
    }
    
    private func storeSecurely(_ value: Any, forKey key: String) {
        do {
            let data: Data
            
            if let stringValue = value as? String {
                data = stringValue.data(using: .utf8) ?? Data()
            } else {
                data = try JSONSerialization.data(withJSONObject: value, options: [])
            }
            
            _ = storeEncrypted(data, forKey: key)
        } catch {
            Logger.error("Failed to serialize value for secure storage: \(error)")
        }
    }
    
    private func getSecureValue(forKey key: String) -> Any? {
        guard let data = getEncrypted(forKey: key) else {
            return nil
        }
        
        // Try to deserialize as string first
        if let stringValue = String(data: data, encoding: .utf8) {
            return stringValue
        }
        
        // Try to deserialize as JSON
        do {
            return try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            Logger.error("Failed to deserialize secure value: \(error)")
            return nil
        }
    }
    
    private func removeSecureValue(forKey key: String) {
        removeFromKeychain(forKey: key)
    }
    
    private func storeInKeychain(_ data: Data, forKey key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keyService,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete existing item first
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error("Failed to store in keychain for key \(key): \(status)")
            return false
        }
        
        return true
    }
    
    private func getFromKeychain(forKey key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keyService,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        } else if status != errSecItemNotFound {
            Logger.error("Failed to get from keychain for key \(key): \(status)")
        }
        
        return nil
    }
    
    private func removeFromKeychain(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keyService,
            kSecAttrAccount: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error("Failed to remove from keychain for key \(key): \(status)")
        }
    }
}

// MARK: - File Storage Extension

extension StorageHelper {
    
    func storeToFile(_ data: Data, fileName: String, encrypted: Bool = true) -> Bool {
        guard let documentsDirectory = getDocumentsDirectory() else {
            Logger.error("Could not access documents directory")
            return false
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            let dataToStore = encrypted ? (encryptionHelper.encrypt(data: data) ?? data) : data
            try dataToStore.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            Logger.error("Failed to store file \(fileName): \(error)")
            return false
        }
    }
    
    func loadFromFile(fileName: String, encrypted: Bool = true) -> Data? {
        guard let documentsDirectory = getDocumentsDirectory() else {
            Logger.error("Could not access documents directory")
            return nil
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            let data = try Data(contentsOf: fileURL)
            return encrypted ? (encryptionHelper.decrypt(data: data) ?? data) : data
        } catch {
            Logger.error("Failed to load file \(fileName): \(error)")
            return nil
        }
    }
    
    func removeFile(fileName: String) -> Bool {
        guard let documentsDirectory = getDocumentsDirectory() else {
            return false
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            Logger.error("Failed to remove file \(fileName): \(error)")
            return false
        }
    }
    
    private func getDocumentsDirectory() -> URL? {
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
