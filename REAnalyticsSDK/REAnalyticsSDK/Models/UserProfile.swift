//
//  UserProfile.swift
//  REAnalyticsSDK
//
//  Created by R Sivakumar on 16/09/25.
//

import Foundation

@objc public class UserProfile: NSObject, Codable {
    @objc public var uniqueId: String
    @objc public var email: String?
    @objc public var phone: String?
    @objc public var gender: String?
    @objc public var age: NSNumber?
    @objc public var isEmployed: NSNumber?
    @objc public var maritalStatus: String?
    @objc public var name: String?
    @objc public var country: String?
    @objc public var city: String?
    @objc public var language: String?
    @objc public var timezone: String?
    @objc public var subscriptionStatus: String?
    @objc public var profilePhotoUrl: String?
    @objc public var preferences: [String: Any]?
    @objc public var customAttributes: [String: Any]?
    
    @objc public init(uniqueId: String) {
        self.uniqueId = uniqueId
        super.init()
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case uniqueId, email, phone, gender, age, isEmployed
        case maritalStatus, name, country, city, language
        case timezone, subscriptionStatus, profilePhotoUrl
        case preferences, customAttributes
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        age = try container.decodeIfPresent(NSNumber.self, forKey: .age)
        isEmployed = try container.decodeIfPresent(NSNumber.self, forKey: .isEmployed)
        maritalStatus = try container.decodeIfPresent(String.self, forKey: .maritalStatus)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
        subscriptionStatus = try container.decodeIfPresent(String.self, forKey: .subscriptionStatus)
        profilePhotoUrl = try container.decodeIfPresent(String.self, forKey: .profilePhotoUrl)
        preferences = try container.decodeIfPresent([String: Any].self, forKey: .preferences)
        customAttributes = try container.decodeIfPresent([String: Any].self, forKey: .customAttributes)
        super.init()
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(age, forKey: .age)
        try container.encodeIfPresent(isEmployed, forKey: .isEmployed)
        try container.encodeIfPresent(maritalStatus, forKey: .maritalStatus)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(timezone, forKey: .timezone)
        try container.encodeIfPresent(subscriptionStatus, forKey: .subscriptionStatus)
        try container.encodeIfPresent(profilePhotoUrl, forKey: .profilePhotoUrl)
    }
}
