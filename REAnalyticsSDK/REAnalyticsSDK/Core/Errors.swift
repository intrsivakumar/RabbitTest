import Foundation

@objc public enum AnalyticsError: Int, Error, LocalizedError {
    
    // MARK: - Initialization Errors
    case notInitialized = 1000
    case alreadyInitialized = 1001
    case invalidConfiguration = 1002
    case invalidAppId = 1003
    
    // MARK: - Network Errors
    case networkNotAvailable = 2000
    case invalidRequest = 2001
    case invalidResponse = 2002
    case serverError = 2003
    case noData = 2004
    case timeout = 2005
    case unauthorized = 2006
    
    // MARK: - Storage Errors
    case storageError = 3000
    case keychainError = 3001
    case encryptionError = 3002
    case decryptionError = 3003
    case dataCorrupted = 3004
    
    // MARK: - Event Errors
    case invalidEventName = 4000
    case invalidEventData = 4001
    case eventTooLarge = 4002
    case tooManyEvents = 4003
    
    // MARK: - User Errors
    case invalidUserProfile = 5000
    case userNotFound = 5001
    case consentRequired = 5002
    case consentDenied = 5003
    
    // MARK: - Location Errors
    case locationPermissionDenied = 6000
    case locationServiceDisabled = 6001
    case locationError = 6002
    case geofenceError = 6003
    case tooManyGeofences = 6004
    
    // MARK: - Session Errors
    case sessionError = 7000
    case sessionExpired = 7001
    case invalidSession = 7002
    
    // MARK: - Notification Errors
    case notificationPermissionDenied = 8000
    case notificationError = 8001
    case invalidNotificationPayload = 8002
    case pushTokenError = 8003
    
    // MARK: - Sensor Errors
    case sensorNotAvailable = 9000
    case sensorPermissionDenied = 9001
    case sensorError = 9002
    
    // MARK: - Generic Errors
    case unknownError = 10000
    case operationCancelled = 10001
    case featureNotSupported = 10002
    case invalidState = 10003
    
    public var errorDescription: String? {
        switch self {
        // Initialization
        case .notInitialized:
            return "SDK is not initialized. Call initialize(appId:) first."
        case .alreadyInitialized:
            return "SDK is already initialized."
        case .invalidConfiguration:
            return "Invalid SDK configuration provided."
        case .invalidAppId:
            return "Invalid or missing app ID."
            
        // Network
        case .networkNotAvailable:
            return "Network connection not available."
        case .invalidRequest:
            return "Invalid network request."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError:
            return "Server returned an error."
        case .noData:
            return "No data received from server."
        case .timeout:
            return "Network request timed out."
        case .unauthorized:
            return "Unauthorized access. Check authentication token."
            
        // Storage
        case .storageError:
            return "Storage operation failed."
        case .keychainError:
            return "Keychain access failed."
        case .encryptionError:
            return "Data encryption failed."
        case .decryptionError:
            return "Data decryption failed."
        case .dataCorrupted:
            return "Stored data is corrupted."
            
        // Events
        case .invalidEventName:
            return "Invalid event name provided."
        case .invalidEventData:
            return "Invalid event data provided."
        case .eventTooLarge:
            return "Event data exceeds size limit."
        case .tooManyEvents:
            return "Too many events in queue."
            
        // User
        case .invalidUserProfile:
            return "Invalid user profile data."
        case .userNotFound:
            return "User not found."
        case .consentRequired:
            return "User consent is required for this operation."
        case .consentDenied:
            return "User consent has been denied."
            
        // Location
        case .locationPermissionDenied:
            return "Location permission denied by user."
        case .locationServiceDisabled:
            return "Location services are disabled."
        case .locationError:
            return "Location tracking error."
        case .geofenceError:
            return "Geofence operation failed."
        case .tooManyGeofences:
            return "Too many geofences being monitored."
            
        // Session
        case .sessionError:
            return "Session management error."
        case .sessionExpired:
            return "Current session has expired."
        case .invalidSession:
            return "Invalid session data."
            
        // Notifications
        case .notificationPermissionDenied:
            return "Notification permission denied by user."
        case .notificationError:
            return "Notification operation failed."
        case .invalidNotificationPayload:
            return "Invalid notification payload."
        case .pushTokenError:
            return "Push token operation failed."
            
        // Sensors
        case .sensorNotAvailable:
            return "Requested sensor is not available."
        case .sensorPermissionDenied:
            return "Sensor permission denied."
        case .sensorError:
            return "Sensor operation failed."
            
        // Generic
        case .unknownError:
            return "An unknown error occurred."
        case .operationCancelled:
            return "Operation was cancelled."
        case .featureNotSupported:
            return "Feature is not supported on this device."
        case .invalidState:
            return "SDK is in an invalid state for this operation."
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .serverError:
            return "The server encountered an error processing the request."
        case .networkNotAvailable:
            return "No internet connection is available."
        case .locationPermissionDenied:
            return "The app does not have permission to access location services."
        case .notificationPermissionDenied:
            return "The app does not have permission to send notifications."
        default:
            return nil
        }
    }
    
    public var recoverySuggestion: String? {
        switch self {
        case .notInitialized:
            return "Initialize the SDK with a valid app ID before using any features."
        case .networkNotAvailable:
            return "Check your internet connection and try again."
        case .locationPermissionDenied:
            return "Enable location permissions in Settings to use location features."
        case .notificationPermissionDenied:
            return "Enable notification permissions in Settings to receive push notifications."
        case .consentRequired:
            return "Request user consent before collecting analytics data."
        default:
            return nil
        }
    }
}

// MARK: - Internal Error Extensions

extension AnalyticsError {
    
    static func serverError(_ statusCode: Int) -> AnalyticsError {
        switch statusCode {
        case 401, 403:
            return .unauthorized
        case 400...499:
            return .invalidRequest
        case 500...599:
            return .serverError
        default:
            return .unknownError
        }
    }
    
    var isNetworkError: Bool {
        switch self {
        case .networkNotAvailable, .timeout, .serverError, .unauthorized:
            return true
        default:
            return false
        }
    }
    
    var shouldRetry: Bool {
        switch self {
        case .networkNotAvailable, .timeout, .serverError:
            return true
        default:
            return false
        }
    }
}

