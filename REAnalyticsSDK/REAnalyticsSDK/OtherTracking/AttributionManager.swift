
import Foundation
import AdServices
import iAd

class AttributionTracker {
    
    private let networkHandler: NetworkHandler
    private let eventTracker: ManualEventTracker
    private let storageHelper: StorageHelper
    
    init(networkHandler: NetworkHandler = NetworkHandler(),
         eventTracker: ManualEventTracker = ManualEventTracker(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.networkHandler = networkHandler
        self.eventTracker = eventTracker
        self.storageHelper = storageHelper
    }
    
    // MARK: - Public Methods
    
    func trackInstallAttribution() {
        // Check if attribution already tracked
        if storageHelper.getValue(forKey: "attribution_tracked") as? Bool == true {
            return
        }
        
        trackAppleSearchAdsAttribution()
        trackInstallReferrer()
        
        storageHelper.setValue(true, forKey: "attribution_tracked")
    }
    
    func trackDeepLinkAttribution(_ url: URL) {
        let attributionData: [String: Any] = [
            "deep_link_url": url.absoluteString,
            "utm_source": extractUTMParameter(from: url, parameter: "utm_source") ?? "",
            "utm_medium": extractUTMParameter(from: url, parameter: "utm_medium") ?? "",
            "utm_campaign": extractUTMParameter(from: url, parameter: "utm_campaign") ?? "",
            "utm_term": extractUTMParameter(from: url, parameter: "utm_term") ?? "",
            "utm_content": extractUTMParameter(from: url, parameter: "utm_content") ?? "",
            "referrer": url.host ?? "",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "deep_link_attribution", data: attributionData)
        Logger.info("Deep link attribution tracked: \(url.absoluteString)")
    }
    
    func trackReferrer(_ referrer: String) {
        let referrerData: [String: Any] = [
            "referrer": referrer,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "app_referrer", data: referrerData)
    }
    
    // MARK: - Private Methods
    
    private func trackAppleSearchAdsAttribution() {
        if #available(iOS 14.3, *) {
            // Use AdServices framework for iOS 14.3+
            Task {
                do {
                    let attribution = try await AAAttribution.attributionToken()
                    await processAppleSearchAdsAttribution(attribution)
                } catch {
                    Logger.error("Failed to get Apple Search Ads attribution: \(error)")
                }
            }
        } else {
            // Use iAd framework for older versions
            ADClient.shared().requestAttributionDetails { attributionDetails, error in
                if let error = error {
                    Logger.error("Failed to get iAd attribution: \(error)")
                    return
                }
                
                if let details = attributionDetails {
                    self.processLegacyAppleSearchAdsAttribution(details)
                }
            }
        }
    }
    
    @available(iOS 14.3, *)
    private func processAppleSearchAdsAttribution(_ token: String) async {
        let attributionData: [String: Any] = [
            "attribution_token": token,
            "attribution_source": "apple_search_ads",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        eventTracker.trackEvent(name: "install_attribution", data: attributionData)
        
        // Send to server for validation
        networkHandler.sendInstallAttribution(attributionData) { result in
            switch result {
            case .success:
                Logger.info("Apple Search Ads attribution sent successfully")
            case .failure(let error):
                Logger.error("Failed to send Apple Search Ads attribution: \(error)")
            }
        }
    }
    
    private func processLegacyAppleSearchAdsAttribution(_ details: [String: NSObject]) {
        var attributionData: [String: Any] = [
            "attribution_source": "apple_search_ads_legacy",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        // Extract available attribution data
        for (key, value) in details {
            attributionData[key] = value
        }
        
        eventTracker.trackEvent(name: "install_attribution", data: attributionData)
        Logger.info("Legacy Apple Search Ads attribution tracked")
    }
    
    private func trackInstallReferrer() {
        // Check for custom install referrer from app launch
        if let referrer = storageHelper.getValue(forKey: "install_referrer") as? String {
            trackReferrer(referrer)
        }
    }
    
    private func extractUTMParameter(from url: URL, parameter: String) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }
        
        return queryItems.first(where: { $0.name == parameter })?.value
    }
}
