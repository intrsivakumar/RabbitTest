import Foundation
import UIKit

@objc public class AnalyticsSDK: NSObject {
    @objc public static let shared = AnalyticsSDK()
    
    private var config: SDKConfig?
    private var isInitialized = false
    
    // Managers
    private lazy var userTracker = UserTrackingManager()
    private lazy var eventTracker = ManualEventTracker()
    private lazy var autoEventTracker = AutoEventTracker()
    private lazy var locationManager = LocationManager()
    lazy var screenTracker = ScreenTracker()
    private lazy var sessionManager = SessionManager()
    private lazy var networkHandler = NetworkHandler()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    @objc public func initialize(appId: String, config: SDKConfig? = nil) {
        guard !isInitialized else {
            Logger.warning("SDK already initialized")
            return
        }
        
        self.config = config ?? SDKConfig.default
        
        // Validate and store appId securely
        StorageHelper.storeAppId(appId)
        
        // Initialize managers
        setupManagers()
        
        isInitialized = true
        Logger.info("Analytics SDK initialized successfully")
    }
    
    @objc public func setUserDetails(user: UserProfile) {
        guard isInitialized else {
            Logger.error("SDK not initialized")
            return
        }
        userTracker.setUserDetails(user)
    }
    
    @objc public func trackEvent(name: String, data: [String: Any]? = nil) {
        guard isInitialized else {
            Logger.error("SDK not initialized")
            return
        }
        eventTracker.trackEvent(name: name, data: data!)
    }
    
    @objc public func trackScreenView(name: String, data: [String: Any]? = nil) {
        guard isInitialized else {
            Logger.error("SDK not initialized")
            return
        }
        screenTracker.trackScreenView(name: name, data: data)
    }
    
    // MARK: - Private Methods
    
    private func setupManagers() {
        sessionManager.startSession()
        autoEventTracker.startTracking()
        
        if config?.locationTrackingEnabled == true {
            locationManager.startTracking()
        }
        
        if config?.screenTrackingEnabled == true {
            screenTracker.startAutomaticTracking()
        }
    }
}

