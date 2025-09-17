
import Foundation
import Network

class NetworkHandler: NSObject {
    
    private let session: URLSession
    private let baseURL: URL
    private let encryptionHelper = EncryptionHelper()
    
    init(baseURL: String = "https://api.analytics-sdk.com") {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.baseURL = URL(string: baseURL)!
        super.init()
    }
    
    // MARK: - Public Methods
    
    func sendEvent(_ event: Event, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let request = createRequest(for: "events", method: "POST", body: event) else {
            completion(.failure(AnalyticsError.invalidRequest))
            return
        }
        
        performRequest(request, retries: 3, completion: completion)
    }
    
    func sendUserProfile(_ profile: UserProfile, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let request = createRequest(for: "users", method: "PUT", body: profile) else {
            completion(.failure(AnalyticsError.invalidRequest))
            return
        }
        
        performRequest(request, retries: 3, completion: completion)
    }
    
    // In your UserTracking class, update the deleteUser method:

    @objc public func deleteUser() {
        guard let userId = StorageHelper.getUserId() else {
            Logger.warning("No user ID found for deletion")
            return
        }
        
        // Check consent
        guard ConsentManager.shared.hasConsent(for: .analytics) else {
            Logger.warning("User consent required for deletion")
            return
        }
        
        networkHandler.deleteUser(userId) { result in
            switch result {
            case .success:
                Logger.info("User deleted from server successfully")
                
                // Clear local user data
                self.clearLocalUserData()
                
                // Track deletion event (if appropriate)
                self.eventTracker.trackEvent(name: "user_deleted", data: [
                    "user_id": userId,
                    "deletion_timestamp": ISO8601DateFormatter().string(from: Date()),
                    "initiated_by": "user"
                ])
                
            case .failure(let error):
                Logger.error("Failed to delete user from server: \(error)")
                
                // Optionally notify the app about the failure
                NotificationCenter.default.post(
                    name: .userDeletionFailed,
                    object: nil,
                    userInfo: ["error": error, "userId": userId]
                )
            }
        }
    }

    private func clearLocalUserData() {
        // Clear user data from local storage
        StorageHelper.clearUserData()
        
        // Reset user profile
        currentUserProfile = nil
        
        // Clear any cached user information
        StorageHelper.removeValue(forKey: Constants.Storage.userId)
        StorageHelper.removeValue(forKey: Constants.Storage.userProfile)
        
        Logger.info("Local user data cleared")
    }

    
    func syncGeofences(completion: @escaping (Result<[GeofenceDefinition], Error>) -> Void) {
        guard let request = createRequest(for: "geofences", method: "GET") else {
            completion(.failure(AnalyticsError.invalidRequest))
            return
        }
        
        performRequestWithResponse(request, responseType: GeofenceResponse.self) { result in
            switch result {
            case .success(let response):
                completion(.success(response.geofences))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func createRequest<T: Codable>(for endpoint: String, method: String, body: T? = nil) -> URLRequest? {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Add headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(StorageHelper.getAppId(), forHTTPHeaderField: "X-App-ID")
        request.setValue(StorageHelper.getDeviceId(), forHTTPHeaderField: "X-Device-ID")
        
        // Add authentication token if available
        if let token = StorageHelper.getAuthToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Encode and encrypt body if provided
        if let body = body {
            do {
                let jsonData = try JSONEncoder().encode(body)
                let encryptedData = encryptionHelper.encrypt(data: jsonData)
                request.httpBody = encryptedData
                
                // Add HMAC signature
                let signature = encryptionHelper.generateHMAC(for: encryptedData!)
                request.setValue(signature, forHTTPHeaderField: "X-Signature")
            } catch {
                Logger.error("Failed to encode request body: \(error)")
                return nil
            }
        }
        
        return request
    }
    
    private func performRequest(_ request: URLRequest, retries: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                if retries > 0 && self.shouldRetry(error: error) {
                    DispatchQueue.global().asyncAfter(deadline: .now() + self.retryDelay(for: 3 - retries)) {
                        self.performRequest(request, retries: retries - 1, completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(AnalyticsError.invalidResponse))
                return
            }
            
            if 200...299 ~= httpResponse.statusCode {
                completion(.success(()))
            } else {
                completion(.failure(AnalyticsError.serverError(httpResponse.statusCode)))
            }
        }.resume()
    }
    
    private func performRequestWithResponse<T: Codable>(_ request: URLRequest, responseType: T.Type, completion: @escaping (Result<T, Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(AnalyticsError.noData))
                return
            }
            
            do {
                // Decrypt response data
                let decryptedData = self.encryptionHelper.decrypt(data: data)
                let responseObject = try JSONDecoder().decode(T.self, from: decryptedData!)
                completion(.success(responseObject))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private func shouldRetry(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    private func retryDelay(for attempt: Int) -> TimeInterval {
        return pow(2.0, Double(attempt)) // Exponential backoff
    }
}

// MARK: - Response Models

private struct GeofenceResponse: Codable {
    let geofences: [GeofenceDefinition]
}
