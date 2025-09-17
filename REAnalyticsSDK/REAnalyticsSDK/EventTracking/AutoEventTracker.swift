
import Foundation
import UIKit

class AutoEventTracker: NSObject {
    
    private let eventTracker: ManualEventTracker
    private let sessionManager: SessionManager
    private let deviceInfoCollector: DeviceInfoCollector
    private let consentManager: ConsentManager
    
    private var isTracking = false
    private var appLaunchTime: Date?
    private var backgroundTime: Date?
    private var currentScreen: String?
    private var screenStartTime: Date?
    
    init(eventTracker: ManualEventTracker = ManualEventTracker(),
         sessionManager: SessionManager = SessionManager.shared,
         deviceInfoCollector: DeviceInfoCollector = DeviceInfoCollector(),
         consentManager: ConsentManager = ConsentManager.shared) {
        self.eventTracker = eventTracker
        self.sessionManager = sessionManager
        self.deviceInfoCollector = deviceInfoCollector
        self.consentManager = consentManager
        super.init()
    }
    
    // MARK: - Public Methods
    
    func startTracking() {
        guard !isTracking else { return }
        guard consentManager.hasConsent(for: .analytics) else {
            Logger.warning("User consent required for automatic event tracking")
            return
        }
        
        setupNotificationObservers()
        trackAppInstallIfNeeded()
        isTracking = true
        
        Logger.info("Automatic event tracking started")
    }
    
    func stopTracking() {
        guard isTracking else { return }
        
        removeNotificationObservers()
        isTracking = false
        
        Logger.info("Automatic event tracking stopped")
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidFinishLaunching),
            name: UIApplication.didFinishLaunchingNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidFinishLaunching() {
        appLaunchTime = Date()
        trackAppLaunch()
    }
    
    @objc private func appDidBecomeActive() {
        trackAppForeground()
        
        // Start session if not already active
        if sessionManager.getCurrentSessionId() == nil {
            sessionManager.startSession()
        }
    }
    
    @objc private func appWillResignActive() {
        // Track time spent in foreground
        if let backgroundStart = backgroundTime {
            let foregroundDuration = Date().timeIntervalSince(backgroundStart)
            trackAppBackground(foregroundDuration: foregroundDuration)
        }
    }
    
    @objc private func appDidEnterBackground() {
        backgroundTime = Date()
        trackScreenViewEnd()
    }
    
    @objc private func appWillEnterForeground() {
        if let backgroundStart = backgroundTime {
            let backgroundDuration = Date().timeIntervalSince(backgroundStart)
            trackAppForeground(backgroundDuration: backgroundDuration)
        }
        backgroundTime = nil
    }
    
    // MARK: - Event Tracking Methods
    
    private func trackAppInstallIfNeeded() {
        let installKey = "analytics_sdk_app_installed"
        
        if !UserDefaults.standard.bool(forKey: installKey) {
            let installData: [String: Any] = [
                "install_timestamp": ISO8601DateFormatter().string(from: Date()),
                "sdk_version": Constants.sdkVersion,
                "app_version": deviceInfoCollector.getAppVersion(),
                "device_platform": deviceInfoCollector.getDevicePlatform(),
                "os_version": deviceInfoCollector.getOSVersion()
            ]
            
            eventTracker.trackEvent(name: Constants.Events.AutoEvents.appInstall, data: installData)
            UserDefaults.standard.set(true, forKey: installKey)
            
            Logger.info("App install event tracked")
        }
    }
    
    private func trackAppLaunch() {
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "analytics_sdk_app_launched_before")
        let launchType = determineLaunchType()
        
        var launchData: [String: Any] = [
            "launch_type": launchType,
            "is_first_launch": isFirstLaunch,
            "sdk_version": Constants.sdkVersion,
            "app_version": deviceInfoCollector.getAppVersion(),
            "device_platform": deviceInfoCollector.getDevicePlatform(),
            "os_version": deviceInfoCollector.getOSVersion(),
            "launch_timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let backgroundStart = backgroundTime {
            let backgroundDuration = Date().timeIntervalSince(backgroundStart)
            launchData["background_duration"] = backgroundDuration
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.appLaunch, data: launchData)
        
        if !isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "analytics_sdk_app_launched_before")
        }
        
        Logger.info("App launch event tracked: \(launchType)")
    }
    
    private func trackAppForeground(backgroundDuration: TimeInterval? = nil) {
        var foregroundData: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? ""
        ]
        
        if let duration = backgroundDuration {
            foregroundData["background_duration"] = duration
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.appForeground, data: foregroundData)
        Logger.info("App foreground event tracked")
    }
    
    private func trackAppBackground(foregroundDuration: TimeInterval) {
        let backgroundData: [String: Any] = [
            "foreground_duration": foregroundDuration,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.appBackground, data: backgroundData)
        Logger.info("App background event tracked")
    }
    
    func trackScreenView(screenName: String, screenClass: String? = nil, previousScreen: String? = nil) {
        // End previous screen tracking
        trackScreenViewEnd()
        
        // Start new screen tracking
        currentScreen = screenName
        screenStartTime = Date()
        
        let screenData: [String: Any] = [
            "screen_name": screenName,
            "screen_class": screenClass ?? "",
            "previous_screen_name": previousScreen ?? currentScreen ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.screenView, data: screenData)
        Logger.info("Screen view tracked: \(screenName)")
    }
    
    private func trackScreenViewEnd() {
        guard let screenName = currentScreen,
              let startTime = screenStartTime else { return }
        
        let timeOnScreen = Date().timeIntervalSince(startTime)
        
        let screenEndData: [String: Any] = [
            "screen_name": screenName,
            "time_on_screen": timeOnScreen,
            "end_timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "screen_view_end", data: screenEndData)
        
        currentScreen = nil
        screenStartTime = nil
    }
    
    // MARK: - Helper Methods
    
    private func determineLaunchType() -> String {
        // Simple heuristic to determine launch type
        let launchInterval = Date().timeIntervalSince(appLaunchTime ?? Date())
        return launchInterval < 2.0 ? "cold_start" : "warm_start"
    }
}

// MARK: - Crash Tracking Extension

extension AutoEventTracker {
    
    func setupCrashTracking() {
        // Set up crash signal handlers
        signal(SIGABRT) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGABRT")
        }
        
        signal(SIGILL) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGILL")
        }
        
        signal(SIGSEGV) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGSEGV")
        }
        
        signal(SIGFPE) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGFPE")
        }
        
        signal(SIGBUS) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGBUS")
        }
        
        signal(SIGPIPE) { signal in
            AutoEventTracker.handleCrash(signal: signal, type: "SIGPIPE")
        }
        
        // Set up NSException handler
        NSSetUncaughtExceptionHandler { exception in
            AutoEventTracker.handleException(exception)
        }
    }
    
    private static func handleCrash(signal: Int32, type: String) {
        let crashData: [String: Any] = [
            "crash_type": "signal",
            "crash_signal": type,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "app_state": UIApplication.shared.applicationState.rawValue
        ]
        
        // Store crash data for next launch
        UserDefaults.standard.set(crashData, forKey: "analytics_sdk_crash_data")
        UserDefaults.standard.synchronize()
    }
    
    private static func handleException(_ exception: NSException) {
        let crashData: [String: Any] = [
            "crash_type": "exception",
            "exception_name": exception.name.rawValue,
            "exception_reason": exception.reason ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "app_state": UIApplication.shared.applicationState.rawValue
        ]
        
        // Store crash data for next launch
        UserDefaults.standard.set(crashData, forKey: "analytics_sdk_crash_data")
        UserDefaults.standard.synchronize()
    }
    
    func checkAndTrackPreviousCrash() {
        if let crashData = UserDefaults.standard.dictionary(forKey: "analytics_sdk_crash_data") {
            eventTracker.trackEvent(name: Constants.Events.AutoEvents.appCrash, data: crashData)
            UserDefaults.standard.removeObject(forKey: "analytics_sdk_crash_data")
            Logger.info("Previous crash tracked")
        }
    }
}
