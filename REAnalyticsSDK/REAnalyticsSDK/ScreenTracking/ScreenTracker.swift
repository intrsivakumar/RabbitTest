
import Foundation
import UIKit

class ScreenTracker: NSObject {
    
    private let eventTracker: ManualEventTracker
    private let sessionManager: SessionManager
    private let consentManager: ConsentManager
    
    private var currentScreen: String?
    private var screenStartTime: Date?
    private var previousScreen: String?
    private var isAutomaticTrackingEnabled = false
    private var screenInteractionCount = 0
    private var maxScrollDepth: Double = 0
    
    init(eventTracker: ManualEventTracker = ManualEventTracker(),
         sessionManager: SessionManager = SessionManager.shared,
         consentManager: ConsentManager = ConsentManager.shared) {
        self.eventTracker = eventTracker
        self.sessionManager = sessionManager
        self.consentManager = consentManager
        super.init()
    }
    
    // MARK: - Public Methods
    
    func startAutomaticTracking() {
        guard consentManager.hasConsent(for: .analytics) else {
            Logger.warning("User consent required for screen tracking")
            return
        }
        
        guard !isAutomaticTrackingEnabled else { return }
        
        setupViewControllerSwizzling()
        setupNotificationObservers()
        isAutomaticTrackingEnabled = true
        
        Logger.info("Automatic screen tracking started")
    }
    
    func stopAutomaticTracking() {
        guard isAutomaticTrackingEnabled else { return }
        
        removeNotificationObservers()
        isAutomaticTrackingEnabled = false
        
        Logger.info("Automatic screen tracking stopped")
    }
    
    func trackScreenView(name: String, data: [String: Any]? = nil) {
        guard consentManager.hasConsent(for: .analytics) else { return }
        
        trackScreenEnd()
        startScreenTracking(screenName: name, data: data)
    }
    
    func trackScreenInteraction() {
        screenInteractionCount += 1
    }
    
    func trackScrollDepth(_ depth: Double) {
        maxScrollDepth = max(maxScrollDepth, depth)
    }
    
    // MARK: - Private Methods
    
    private func setupViewControllerSwizzling() {
        swizzleViewControllerMethods()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appDidEnterBackground() {
        trackScreenEnd()
    }
    
    private func startScreenTracking(screenName: String, data: [String: Any]? = nil) {
        previousScreen = currentScreen
        currentScreen = screenName
        screenStartTime = Date()
        screenInteractionCount = 0
        maxScrollDepth = 0
        
        var screenData: [String: Any] = [
            "screen_name": screenName,
            "screen_class": extractScreenClass(from: screenName),
            "previous_screen_name": previousScreen ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? "",
            "navigation_method": determineNavigationMethod()
        ]
        
        // Add custom data if provided
        if let data = data {
            for (key, value) in data {
                screenData["custom_\(key)"] = value
            }
        }
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.screenView, data: screenData)
        
        // Update session with screen view
        sessionManager.addScreenView(screenName)
        
        Logger.debug("Screen view tracked: \(screenName)")
    }
    
    private func trackScreenEnd() {
        guard let screenName = currentScreen,
              let startTime = screenStartTime else { return }
        
        let timeOnScreen = Date().timeIntervalSince(startTime)
        
        let screenEndData: [String: Any] = [
            "screen_name": screenName,
            "time_on_screen": timeOnScreen,
            "interaction_count": screenInteractionCount,
            "scroll_depth": maxScrollDepth,
            "end_timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": sessionManager.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "screen_view_end", data: screenEndData)
        
        currentScreen = nil
        screenStartTime = nil
        screenInteractionCount = 0
        maxScrollDepth = 0
    }
    
    private func extractScreenClass(from screenName: String) -> String {
        // Try to extract the actual class name from the screen name
        if screenName.contains("ViewController") {
            return screenName
        }
        return "\(screenName)ViewController"
    }
    
    private func determineNavigationMethod() -> String {
        // Simple heuristic to determine navigation method
        // In a real implementation, this could be more sophisticated
        if previousScreen == nil {
            return "app_launch"
        } else if previousScreen?.contains("Tab") == true || currentScreen?.contains("Tab") == true {
            return "tab_bar"
        } else {
            return "navigation_push"
        }
    }
    
    private func swizzleViewControllerMethods() {
        // Method swizzling for automatic screen tracking
        let originalSelector = #selector(UIViewController.viewDidAppear(_:))
        let swizzledSelector = #selector(UIViewController.analytics_viewDidAppear(_:))
        
        guard let originalMethod = class_getInstanceMethod(UIViewController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIViewController.self, swizzledSelector) else {
            Logger.error("Failed to get methods for swizzling")
            return
        }
        
        let didAddMethod = class_addMethod(
            UIViewController.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )
        
        if didAddMethod {
            class_replaceMethod(
                UIViewController.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }
}

// MARK: - UIViewController Extension

extension UIViewController {
    
    @objc func analytics_viewDidAppear(_ animated: Bool) {
        analytics_viewDidAppear(animated) // Call original implementation
        
        // Track screen view
        let screenName = title ?? String(describing: type(of: self))
        ScreenTracker.shared?.handleViewControllerAppear(screenName: screenName, viewController: self)
    }
}

// MARK: - ScreenTracker Extension

extension ScreenTracker {
    
    static var shared: ScreenTracker? {
        return AnalyticsSDK.shared.screenTracker
    }
    
    func handleViewControllerAppear(screenName: String, viewController: UIViewController) {
        guard isAutomaticTrackingEnabled else { return }
        
        var customData: [String: Any] = [:]
        
        // Extract additional properties if available
        if let tabBarController = viewController.tabBarController {
            customData["tab_index"] = tabBarController.selectedIndex
        }
        
        if let navigationController = viewController.navigationController {
            customData["navigation_depth"] = navigationController.viewControllers.count
        }
        
        startScreenTracking(screenName: screenName, data: customData)
    }
}
