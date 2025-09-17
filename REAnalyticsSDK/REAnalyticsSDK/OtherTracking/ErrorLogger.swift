
import Foundation
import UIKit

class ErrorTracker {
    
    private let eventTracker: ManualEventTracker
    private let networkHandler: NetworkHandler
    private var isErrorHandlerSetup = false
    
    init(eventTracker: ManualEventTracker = ManualEventTracker(),
         networkHandler: NetworkHandler = NetworkHandler()) {
        self.eventTracker = eventTracker
        self.networkHandler = networkHandler
    }
    
    // MARK: - Public Methods
    
    func setupErrorTracking() {
        guard !isErrorHandlerSetup else { return }
        
        setupExceptionHandler()
        setupSignalHandler()
        isErrorHandlerSetup = true
        
        Logger.info("Error tracking setup completed")
    }
    
    func trackError(_ error: Error, context: [String: Any] = [:]) {
        let errorData: [String: Any] = [
            "error_domain": (error as NSError).domain,
            "error_code": (error as NSError).code,
            "error_description": error.localizedDescription,
            "error_context": context,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? "",
            "app_version": DeviceInfoCollector().getAppVersion(),
            "os_version": DeviceInfoCollector().getOSVersion(),
            "device_model": DeviceInfoCollector().getCurrentDeviceInfo()["device_model"] ?? ""
        ]
        
        eventTracker.trackEvent(name: "sdk_error", data: errorData)
        Logger.error("SDK Error tracked: \(error.localizedDescription)")
    }
    
    func trackCrash(_ crashInfo: [String: Any]) {
        var crashData = crashInfo
        crashData["timestamp"] = ISO8601DateFormatter().string(from: Date())
        crashData["session_id"] = SessionManager.shared.getCurrentSessionId() ?? ""
        crashData["app_version"] = DeviceInfoCollector().getAppVersion()
        crashData["os_version"] = DeviceInfoCollector().getOSVersion()
        
        eventTracker.trackEvent(name: Constants.Events.AutoEvents.appCrash, data: crashData)
        
        // Send crash report immediately
        networkHandler.sendCrashReport(crashData) { result in
            switch result {
            case .success:
                Logger.info("Crash report sent successfully")
            case .failure(let error):
                Logger.error("Failed to send crash report: \(error)")
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let crashInfo: [String: Any] = [
                "crash_type": "exception",
                "exception_name": exception.name.rawValue,
                "exception_reason": exception.reason ?? "",
                "exception_stack": exception.callStackSymbols,
                "app_state": UIApplication.shared.applicationState.rawValue
            ]
            
            ErrorTracker.shared?.trackCrash(crashInfo)
        }
    }
    
    private func setupSignalHandler() {
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS]
        
        for signal in signals {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = { signal in
                let crashInfo: [String: Any] = [
                    "crash_type": "signal",
                    "signal": signal,
                    "signal_name": ErrorTracker.signalName(for: signal),
                    "app_state": UIApplication.shared.applicationState.rawValue
                ]
                
                ErrorTracker.shared?.trackCrash(crashInfo)
            }
            
            sigaction(signal, &action, nil)
        }
    }
    
    private static func signalName(for signal: Int32) -> String {
        switch signal {
        case SIGABRT:
            return "SIGABRT"
        case SIGILL:
            return "SIGILL"
        case SIGSEGV:
            return "SIGSEGV"
        case SIGFPE:
            return "SIGFPE"
        case SIGBUS:
            return "SIGBUS"
        default:
            return "UNKNOWN"
        }
    }
    
    // MARK: - Singleton
    
    private static var shared: ErrorTracker?
    
    static func initialize() {
        shared = ErrorTracker()
        shared?.setupErrorTracking()
    }
}
