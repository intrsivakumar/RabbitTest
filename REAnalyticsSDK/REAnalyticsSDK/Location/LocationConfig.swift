
import Foundation
import CoreLocation

@objc public class LocationConfig: NSObject, Codable {
    
    @objc public var enableAutoTracking: Bool = false
    @objc public var accuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    @objc public var distanceFilter: CLLocationDistance = 100
    @objc public var requestAlwaysPermission: Bool = false
    @objc public var anonymizeLocation: Bool = false
    @objc public var locationCacheSize: Int = 100
    @objc public var batchUploadInterval: TimeInterval = 300 // 5 minutes
    
    public override init() {
        super.init()
    }
    
    @objc public init(enableAutoTracking: Bool = false,
                      accuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters,
                      distanceFilter: CLLocationDistance = 100,
                      requestAlwaysPermission: Bool = false,
                      anonymizeLocation: Bool = false) {
        self.enableAutoTracking = enableAutoTracking
        self.accuracy = accuracy
        self.distanceFilter = distanceFilter
        self.requestAlwaysPermission = requestAlwaysPermission
        self.anonymizeLocation = anonymizeLocation
        super.init()
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case enableAutoTracking, accuracy, distanceFilter
        case requestAlwaysPermission, anonymizeLocation
        case locationCacheSize, batchUploadInterval
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enableAutoTracking = try container.decode(Bool.self, forKey: .enableAutoTracking)
        accuracy = try container.decode(CLLocationAccuracy.self, forKey: .accuracy)
        distanceFilter = try container.decode(CLLocationDistance.self, forKey: .distanceFilter)
        requestAlwaysPermission = try container.decode(Bool.self, forKey: .requestAlwaysPermission)
        anonymizeLocation = try container.decode(Bool.self, forKey: .anonymizeLocation)
        locationCacheSize = try container.decode(Int.self, forKey: .locationCacheSize)
        batchUploadInterval = try container.decode(TimeInterval.self, forKey: .batchUploadInterval)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enableAutoTracking, forKey: .enableAutoTracking)
        try container.encode(accuracy, forKey: .accuracy)
        try container.encode(distanceFilter, forKey: .distanceFilter)
        try container.encode(requestAlwaysPermission, forKey: .requestAlwaysPermission)
        try container.encode(anonymizeLocation, forKey: .anonymizeLocation)
        try container.encode(locationCacheSize, forKey: .locationCacheSize)
        try container.encode(batchUploadInterval, forKey: .batchUploadInterval)
    }
}
