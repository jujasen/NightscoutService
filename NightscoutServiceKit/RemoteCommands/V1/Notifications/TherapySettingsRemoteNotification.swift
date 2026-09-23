//
//  TherapySettingsRemoteNotification.swift
//  NightscoutServiceKit
//
//  A caregiver app (LoopFollow) replacing the carb ratio and/or insulin sensitivity schedule:
//
//  { "therapy-settings": { "carb-ratio": [{"start": 0, "value": 12}, {"start": 21600, "value": 10}],
//                          "insulin-sensitivity": [{"start": 0, "value": 9.5}],
//                          "insulin-sensitivity-unit": "mmol/L" },
//    "otp": "123456", "remote-address": "LoopFollow", "sent-at": "…", "expiration": "…" }
//

import Foundation
import LoopKit

public struct TherapySettingsRemoteNotification: RemoteNotification, Codable {

    public let therapySettings: TherapySettingsAction
    public let remoteAddress: String
    public let expiration: Date?
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    enum CodingKeys: String, CodingKey {
        case therapySettings = "therapy-settings"
        case remoteAddress = "remote-address"
        case expiration = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        return .therapySettings(therapySettings)
    }

    /// Changing dosing settings is as consequential as a bolus.
    func otpValidationRequired() -> Bool {
        return true
    }

    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        return notification["therapy-settings"] != nil
    }
}
