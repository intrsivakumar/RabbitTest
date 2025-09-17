
import Foundation
import CommonCrypto
import Security

class EncryptionHelper {
    
    private let keyService = "com.analytics.sdk.encryption"
    private let keyAccount = "encryption_key"
    
    init() {
        generateEncryptionKeyIfNeeded()
    }
    
    // MARK: - Public Methods
    
    func encrypt(data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            Logger.error("Failed to get encryption key")
            return nil
        }
        
        return aesEncrypt(data: data, key: key)
    }
    
    func decrypt(data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            Logger.error("Failed to get encryption key")
            return nil
        }
        
        return aesDecrypt(data: data, key: key)
    }
    
    func encrypt(string: String) -> String? {
        guard let data = string.data(using: .utf8),
              let encryptedData = encrypt(data: data) else {
            return nil
        }
        
        return encryptedData.base64EncodedString()
    }
    
    func decrypt(string: String) -> String? {
        guard let data = Data(base64Encoded: string),
              let decryptedData = decrypt(data: data) else {
            return nil
        }
        
        return String(data: decryptedData, encoding: .utf8)
    }
    
    func generateHMAC(for data: Data) -> String? {
        guard let key = getHMACKey() else {
            Logger.error("Failed to get HMAC key")
            return nil
        }
        
        return hmacSHA256(data: data, key: key)
    }
    
    func verifyHMAC(_ hmac: String, for data: Data) -> Bool {
        guard let expectedHMAC = generateHMAC(for: data) else {
            return false
        }
        
        return hmac == expectedHMAC
    }
    
    func hash(string: String) -> String? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        
        return sha256Hash(data: data)
    }
    
    // MARK: - Private Methods
    
    private func generateEncryptionKeyIfNeeded() {
        if getEncryptionKey() == nil {
            generateAndStoreEncryptionKey()
        }
        
        if getHMACKey() == nil {
            generateAndStoreHMACKey()
        }
    }
    
    private func generateAndStoreEncryptionKey() {
        let key = generateRandomKey(size: Constants.Security.encryptionKeySize)
        storeKeyInKeychain(key, account: keyAccount)
    }
    
    private func generateAndStoreHMACKey() {
        let key = generateRandomKey(size: Constants.Security.hmacKeySize)
        storeKeyInKeychain(key, account: "\(keyAccount)_hmac")
    }
    
    private func generateRandomKey(size: Int) -> Data {
        var key = Data(count: size)
        let result = key.withUnsafeMutableBytes { mutableBytes in
            SecRandomCopyBytes(kSecRandomDefault, size, mutableBytes.bindMemory(to: UInt8.self).baseAddress!)
        }
        
        if result != errSecSuccess {
            Logger.error("Failed to generate random key")
        }
        
        return key
    }
    
    private func getEncryptionKey() -> Data? {
        return getKeyFromKeychain(account: keyAccount)
    }
    
    private func getHMACKey() -> Data? {
        return getKeyFromKeychain(account: "\(keyAccount)_hmac")
    }
    
    private func storeKeyInKeychain(_ key: Data, account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keyService,
            kSecAttrAccount: account,
            kSecValueData: key,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error("Failed to store key in keychain: \(status)")
        }
    }
    
    private func getKeyFromKeychain(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keyService,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        } else {
            Logger.error("Failed to get key from keychain: \(status)")
            return nil
        }
    }
    
    private func aesEncrypt(data: Data, key: Data) -> Data? {
        let iv = generateRandomIV()
        
        var encryptedData = Data(count: data.count + kCCBlockSizeAES128)
        var encryptedLength: size_t = 0
        
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    encryptedData.withUnsafeMutableBytes { encryptedBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                            key.count,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress!,
                            dataBytes.bindMemory(to: UInt8.self).baseAddress!,
                            data.count,
                            encryptedBytes.bindMemory(to: UInt8.self).baseAddress!,
                            encryptedData.count,
                            &encryptedLength
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            Logger.error("AES encryption failed with status: \(status)")
            return nil
        }
        
        encryptedData.count = encryptedLength
        return iv + encryptedData
    }
    
    private func aesDecrypt(data: Data, key: Data) -> Data? {
        guard data.count > Constants.Security.ivSize else {
            Logger.error("Invalid encrypted data size")
            return nil
        }
        
        let iv = data.prefix(Constants.Security.ivSize)
        let encryptedData = data.dropFirst(Constants.Security.ivSize)
        
        var decryptedData = Data(count: encryptedData.count)
        var decryptedLength: size_t = 0
        
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                encryptedData.withUnsafeBytes { encryptedBytes in
                    decryptedData.withUnsafeMutableBytes { decryptedBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                            key.count,
                            ivBytes.bindMemory(to: UInt8.self).baseAddress!,
                            encryptedBytes.bindMemory(to: UInt8.self).baseAddress!,
                            encryptedData.count,
                            decryptedBytes.bindMemory(to: UInt8.self).baseAddress!,
                            decryptedData.count,
                            &decryptedLength
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            Logger.error("AES decryption failed with status: \(status)")
            return nil
        }
        
        decryptedData.count = decryptedLength
        return decryptedData
    }
    
    private func generateRandomIV() -> Data {
        return generateRandomKey(size: Constants.Security.ivSize)
    }
    
    private func hmacSHA256(data: Data, key: Data) -> String? {
        var hmac = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        
        hmac.withUnsafeMutableBytes { hmacBytes in
            key.withUnsafeBytes { keyBytes in
                data.withUnsafeBytes { dataBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.bindMemory(to: UInt8.self).baseAddress!,
                        key.count,
                        dataBytes.bindMemory(to: UInt8.self).baseAddress!,
                        data.count,
                        hmacBytes.bindMemory(to: UInt8.self).baseAddress!
                    )
                }
            }
        }
        
        return hmac.map { String(format: "%02x", $0) }.joined()
    }
    
    private func sha256Hash(data: Data) -> String? {
        var hash = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        
        data.withUnsafeBytes { dataBytes in
            hash.withUnsafeMutableBytes { hashBytes in
                CC_SHA256(
                    dataBytes.bindMemory(to: UInt8.self).baseAddress!,
                    CC_LONG(data.count),
                    hashBytes.bindMemory(to: UInt8.self).baseAddress!
                )
            }
        }
        
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
