
import Foundation
import UIKit

@objc public class DynamicZoneConfig: NSObject, Codable {
    @objc public var zoneId: String
    @objc public var priority: Int
    @objc public var conditions: [String] // Serialized conditions
    @objc public var displayStyle: DisplayStyle
    @objc public var isActive: Bool
    
    public init(zoneId: String, priority: Int = 0, displayStyle: DisplayStyle = .banner) {
        self.zoneId = zoneId
        self.priority = priority
        self.conditions = []
        self.displayStyle = displayStyle
        self.isActive = true
        super.init()
    }
}

@objc public class DisplayContent: NSObject, Codable {
    @objc public var title: String = ""
    @objc public var message: String = ""
    @objc public var imageUrl: String?
    @objc public var actionUrl: String?
    @objc public var buttonText: String?
    @objc public var backgroundColor: String?
    @objc public var textColor: String?
    @objc public var customData: [String: String] = [:]
    
    public override init() {
        super.init()
    }
}

class DynamicZoneManager {
    
    private let networkHandler: NetworkHandler
    private let ruleEngine: LocalRuleEngine
    private let eventTracker: ManualEventTracker
    private let storageHelper: StorageHelper
    
    private var activeZones: [String: DynamicZoneConfig] = [:]
    private var displayedZones: Set<String> = []
    
    init(networkHandler: NetworkHandler = NetworkHandler(),
         ruleEngine: LocalRuleEngine = LocalRuleEngine(),
         eventTracker: ManualEventTracker = ManualEventTracker(),
         storageHelper: StorageHelper = StorageHelper()) {
        self.networkHandler = networkHandler
        self.ruleEngine = ruleEngine
        self.eventTracker = eventTracker
        self.storageHelper = storageHelper
        
        loadStoredZones()
    }
    
    // MARK: - Public Methods
    
    func setDynamicZoneConfig(_ config: DynamicZoneConfig) {
        activeZones[config.zoneId] = config
        saveZones()
        
        Logger.info("Dynamic zone configured: \(config.zoneId)")
    }
    
    func evaluateDynamicZones() {
        for (zoneId, config) in activeZones where config.isActive {
            evaluateZone(zoneId, config: config)
        }
    }
    
    func presentNativeDisplay(for zoneId: String, with content: DisplayContent) {
        guard let config = activeZones[zoneId],
              !displayedZones.contains(zoneId) else {
            Logger.warning("Zone \(zoneId) not available or already displayed")
            return
        }
        
        displayedZones.insert(zoneId)
        
        DispatchQueue.main.async {
            self.showNativeDisplay(config: config, content: content)
        }
        
        // Track zone display
        trackZoneEvent("zone_displayed", zoneId: zoneId, content: content)
    }
    
    func dismissZone(_ zoneId: String) {
        displayedZones.remove(zoneId)
        
        // Find and dismiss the displayed zone
        DispatchQueue.main.async {
            self.hideNativeDisplay(zoneId: zoneId)
        }
        
        trackZoneEvent("zone_dismissed", zoneId: zoneId, content: nil)
    }
    
    func getActiveZones() -> [DynamicZoneConfig] {
        return Array(activeZones.values.filter { $0.isActive })
    }
    
    // MARK: - Private Methods
    
    private func evaluateZone(_ zoneId: String, config: DynamicZoneConfig) {
        // Check if zone should be displayed based on conditions
        let context = getCurrentContext()
        
        ruleEngine.evaluateConditions(config.conditions, context: context) { [weak self] shouldDisplay, content in
            if shouldDisplay {
                self?.fetchZoneContent(zoneId) { content in
                    if let content = content {
                        self?.presentNativeDisplay(for: zoneId, with: content)
                    }
                }
            }
        }
    }
    
    private func getCurrentContext() -> [String: Any] {
        var context: [String: Any] = [:]
        
        // Session context
        if let sessionId = SessionManager.shared.getCurrentSessionId() {
            context["session_id"] = sessionId
        }
        
        // User context
        if let userId = StorageHelper.getUserId() {
            context["user_id"] = userId
        }
        
        // Device context
        let deviceInfo = DeviceInfoCollector().getCurrentDeviceInfo()
        context.merge(deviceInfo) { _, new in new }
        
        // Location context
        if let location = LocationManager.shared.getCurrentLocation() {
            context["latitude"] = location.coordinate.latitude
            context["longitude"] = location.coordinate.longitude
        }
        
        // Time context
        context["local_time"] = DateFormatter.localTimeFormatter.string(from: Date())
        context["timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        return context
    }
    
    private func fetchZoneContent(_ zoneId: String, completion: @escaping (DisplayContent?) -> Void) {
        let parameters: [String: Any] = [
            "zone_id": zoneId,
            "device_id": StorageHelper.getDeviceId(),
            "user_id": StorageHelper.getUserId() ?? "",
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        networkHandler.fetchDynamicZoneContent(parameters) { result in
            switch result {
            case .success(let data):
                do {
                    let content = try JSONDecoder().decode(DisplayContent.self, from: data)
                    completion(content)
                } catch {
                    Logger.error("Failed to decode zone content: \(error)")
                    completion(nil)
                }
            case .failure(let error):
                Logger.error("Failed to fetch zone content: \(error)")
                completion(nil)
            }
        }
    }
    
    private func showNativeDisplay(config: DynamicZoneConfig, content: DisplayContent) {
        switch config.displayStyle {
        case .banner:
            showBannerDisplay(zoneId: config.zoneId, content: content)
        case .modal:
            showModalDisplay(zoneId: config.zoneId, content: content)
        case .fullScreen:
            showFullScreenDisplay(zoneId: config.zoneId, content: content)
        case .carousel:
            showCarouselDisplay(zoneId: config.zoneId, content: content)
        case .custom:
            showCustomDisplay(zoneId: config.zoneId, content: content)
        }
    }
    
    private func showBannerDisplay(zoneId: String, content: DisplayContent) {
        guard let topVC = getTopViewController() else { return }
        
        let bannerView = DynamicZoneBannerView()
        bannerView.configure(with: content, zoneId: zoneId)
        bannerView.delegate = self
        
        topVC.view.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            bannerView.topAnchor.constraint(equalTo: topVC.view.safeAreaLayoutGuide.topAnchor),
            bannerView.leadingAnchor.constraint(equalTo: topVC.view.leadingAnchor),
            bannerView.trailingAnchor.constraint(equalTo: topVC.view.trailingAnchor),
            bannerView.heightAnchor.constraint(equalToConstant: 80)
        ])
        
        // Animate in
        bannerView.transform = CGAffineTransform(translationX: 0, y: -80)
        UIView.animate(withDuration: 0.3) {
            bannerView.transform = .identity
        }
        
        // Auto-dismiss after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.dismissZone(zoneId)
        }
    }
    
    private func showModalDisplay(zoneId: String, content: DisplayContent) {
        guard let topVC = getTopViewController() else { return }
        
        let modalVC = DynamicZoneModalViewController()
        modalVC.configure(with: content, zoneId: zoneId)
        modalVC.delegate = self
        
        modalVC.modalPresentationStyle = .pageSheet
        topVC.present(modalVC, animated: true)
    }
    
    private func showFullScreenDisplay(zoneId: String, content: DisplayContent) {
        guard let topVC = getTopViewController() else { return }
        
        let fullScreenVC = DynamicZoneFullScreenViewController()
        fullScreenVC.configure(with: content, zoneId: zoneId)
        fullScreenVC.delegate = self
        
        fullScreenVC.modalPresentationStyle = .fullScreen
        topVC.present(fullScreenVC, animated: true)
    }
    
    private func showCarouselDisplay(zoneId: String, content: DisplayContent) {
        // Implementation for carousel display
        showBannerDisplay(zoneId: zoneId, content: content) // Fallback to banner
    }
    
    private func showCustomDisplay(zoneId: String, content: DisplayContent) {
        // Implementation for custom display
        showModalDisplay(zoneId: zoneId, content: content) // Fallback to modal
    }
    
    private func hideNativeDisplay(zoneId: String) {
        // Find and remove the displayed zone view
        guard let topVC = getTopViewController() else { return }
        
        for subview in topVC.view.subviews {
            if let bannerView = subview as? DynamicZoneBannerView,
               bannerView.zoneId == zoneId {
                UIView.animate(withDuration: 0.3, animations: {
                    bannerView.transform = CGAffineTransform(translationX: 0, y: -80)
                    bannerView.alpha = 0
                }) { _ in
                    bannerView.removeFromSuperview()
                }
                break
            }
        }
    }
    
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return nil
        }
        
        var topController = window.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }
    
    private func trackZoneEvent(_ eventName: String, zoneId: String, content: DisplayContent?) {
        var eventData: [String: Any] = [
            "zone_id": zoneId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "session_id": SessionManager.shared.getCurrentSessionId() ?? ""
        ]
        
        if let content = content {
            eventData["content_title"] = content.title
            eventData["content_action_url"] = content.actionUrl
        }
        
        eventTracker.trackEvent(name: eventName, data: eventData)
    }
    
    private func loadStoredZones() {
        guard let data = storageHelper.getValue(forKey: "dynamic_zones") as? Data else { return }
        
        do {
            let zones = try JSONDecoder().decode([String: DynamicZoneConfig].self, from: data)
            activeZones = zones
            Logger.info("Loaded \(zones.count) dynamic zones")
        } catch {
            Logger.error("Failed to load dynamic zones: \(error)")
        }
    }
    
    private func saveZones() {
        do {
            let data = try JSONEncoder().encode(activeZones)
            storageHelper.setValue(data, forKey: "dynamic_zones")
        } catch {
            Logger.error("Failed to save dynamic zones: \(error)")
        }
    }
}

// MARK: - DynamicZoneDelegate

extension DynamicZoneManager: DynamicZoneDelegate {
    
    func dynamicZoneDidAppear(_ zoneId: String) {
        trackZoneEvent("zone_appeared", zoneId: zoneId, content: nil)
    }
    
    func dynamicZoneDidDismiss(_ zoneId: String) {
        displayedZones.remove(zoneId)
        trackZoneEvent("zone_dismissed", zoneId: zoneId, content: nil)
    }
    
    func dynamicZoneDidTapAction(_ zoneId: String, actionUrl: String?) {
        trackZoneEvent("zone_action_tapped", zoneId: zoneId, content: nil)
        
        if let urlString = actionUrl, let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let localTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

protocol DynamicZoneDelegate: AnyObject {
    func dynamicZoneDidAppear(_ zoneId: String)
    func dynamicZoneDidDismiss(_ zoneId: String)
    func dynamicZoneDidTapAction(_ zoneId: String, actionUrl: String?)
}
