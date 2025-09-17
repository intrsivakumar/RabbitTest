
import Foundation
import UIKit
import CoreTelephony
import AdSupport
import AppTrackingTransparency
import Network
import CoreLocation

class DeviceInfoCollector {
    
    private var cachedInfo: [String: Any] = [:]
    private var lastRefreshTime: Date = Date.distantPast
    private let refreshInterval: TimeInterval = 3600 // 1 hour
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    init() {
        setupNetworkMonitoring()
        refreshDeviceInfo()
    }
    
    deinit {
        networkMonitor.cancel()
    }
    
    // MARK: - Public Methods
    
    func getCurrentDeviceInfo() -> [String: Any] {
        let now = Date()
        if now.timeIntervalSince(lastRefreshTime) > refreshInterval {
            refreshDeviceInfo()
        }
        return cachedInfo
    }
    
    func getDeviceId() -> String {
        return UIDevice.current.identifierForVendor?.uuidString ?? ""
    }
    
    func getAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
    
    func getAppBuild() -> String {
        return Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }
    
    func getDevicePlatform() -> String {
        let device = UIDevice.current
        return device.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
    }
    
    func getOSVersion() -> String {
        return UIDevice.current.systemVersion
    }
    
    func getNetworkType() -> String {
        return cachedInfo["network_type"] as? String ?? "unknown"
    }
    
    // MARK: - Private Methods
    
    @discardableResult
    private func refreshDeviceInfo() -> [String: Any] {
        var info: [String: Any] = [:]
        
        // Identifiers
        info["device_id"] = getDeviceId()
        collectAdvertisingIdentifier(&info)
        
        // Hardware Info
        let device = UIDevice.current
        info["device_model"] = deviceModel()
        info["device_name"] = device.name
        info["cpu_cores"] = ProcessInfo.processInfo.processorCount
        info["total_ram"] = ProcessInfo.processInfo.physicalMemory
        collectStorageInfo(&info)
        
        // Software Info
        info["os_name"] = device.systemName
        info["os_version"] = device.systemVersion
        info["locale"] = Locale.current.identifier
        info["time_zone"] = TimeZone.current.identifier
        
        // App Context
        info["app_version"] = getAppVersion()
        info["app_build"] = getAppBuild()
        info["install_source"] = determineInstallSource()
        
        // Network Info
        collectNetworkInfo(&info)
        
        // Device State
        collectDeviceState(&info)
        
        // Permissions
        collectPermissionStatus(&info)
        
        cachedInfo = info
        lastRefreshTime = Date()
        
        return info
    }
    
    private func collectAdvertisingIdentifier(_ info: inout [String: Any]) {
        if #available(iOS 14, *) {
            if ATTrackingManager.trackingAuthorizationStatus == .authorized {
                let advertisingId = ASIdentifierManager.shared().advertisingIdentifier
                if !advertisingId.isEqual(to: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!) {
                    info["ad_id"] = advertisingId.uuidString
                }
            }
        } else {
            if ASIdentifierManager.shared().isAdvertisingTrackingEnabled {
                info["ad_id"] = ASIdentifierManager.shared().advertisingIdentifier.uuidString
            }
        }
    }
    
    private func collectStorageInfo(_ info: inout [String: Any]) {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            
            if let totalSpace = attributes[.systemSize] as? NSNumber {
                info["total_storage"] = totalSpace.doubleValue / (1024 * 1024 * 1024) // Convert to GB
            }
            
            if let freeSpace = attributes[.systemFreeSize] as? NSNumber {
                info["free_storage"] = freeSpace.doubleValue / (1024 * 1024 * 1024) // Convert to GB
            }
        } catch {
            Logger.error("Failed to get storage info: \(error)")
        }
    }
    
    private func collectNetworkInfo(_ info: inout [String: Any]) {
        info["network_type"] = getCurrentNetworkType()
        
        let networkInfo = CTTelephonyNetworkInfo()
        if let carrier = networkInfo.subscriberCellularProvider {
            info["carrier"] = carrier.carrierName
        }
        
        // Get cellular generation
        if let radioTech = networkInfo.currentRadioAccessTechnology {
            info["cellular_generation"] = mapRadioTechToCellularGeneration(radioTech)
        }
    }
    
    private func collectDeviceState(_ info: inout [String: Any]) {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        
        info["battery_level"] = round(device.batteryLevel * 100) / 100 // Round to 2 decimal places
        info["battery_state"] = batteryStateString(device.batteryState)
        info["low_power_mode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
        
        device.isBatteryMonitoringEnabled = false
    }
    
    private func collectPermissionStatus(_ info: inout [String: Any]) {
        // Push notification permission
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    self.cachedInfo["push_enabled"] = settings.authorizationStatus == .authorized
                }
            }
        }
        
        // Location permission
        let locationStatus = CLLocationManager().authorizationStatus
        info["location_permission"] = locationPermissionString(locationStatus)
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let networkType = self?.pathToNetworkType(path) ?? "unknown"
            self?.cachedInfo["network_type"] = networkType
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Helper Methods
    
    private func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    private func determineInstallSource() -> String {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return "unknown"
        }
        
        let receiptURLString = receiptURL.absoluteString
        if receiptURLString.contains("CoreSimulator") {
            return "simulator"
        } else if receiptURLString.contains("sandboxReceipt") {
            return "testflight"
        } else {
            return "app_store"
        }
    }
    
    private func getCurrentNetworkType() -> String {
        let path = networkMonitor.currentPath
        return pathToNetworkType(path)
    }
    
    private func pathToNetworkType(_ path: NWPath) -> String {
        if path.usesInterfaceType(.wifi) {
            return "wifi"
        } else if path.usesInterfaceType(.cellular) {
            return "cellular"
        } else if path.usesInterfaceType(.wiredEthernet) {
            return "ethernet"
        } else if path.status == .satisfied {
            return "other"
        } else {
            return "none"
        }
    }
    
    private func mapRadioTechToCellularGeneration(_ radioTech: String) -> String {
        switch radioTech {
        case CTRadioAccessTechnologyGPRS,
             CTRadioAccessTechnologyEdge,
             CTRadioAccessTechnologyCDMA1x:
            return "2g"
        case CTRadioAccessTechnologyWCDMA,
             CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA,
             CTRadioAccessTechnologyCDMAEVDORev0,
             CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB,
             CTRadioAccessTechnologyeHRPD:
            return "3g"
        case CTRadioAccessTechnologyLTE:
            return "4g"
        default:
            if #available(iOS 14.1, *) {
                if radioTech == CTRadioAccessTechnologyNRNSA || radioTech == CTRadioAccessTechnologyNR {
                    return "5g"
                }
            }
            return "unknown"
        }
    }
    
    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unplugged:
            return "unplugged"
        case .charging:
            return "charging"
        case .full:
            return "full"
        case .unknown:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }
    
    private func locationPermissionString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .authorizedWhenInUse:
            return "when_in_use"
        case .authorizedAlways:
            return "always"
        @unknown default:
            return "unknown"
        }
    }
}



//Test code rabbit
