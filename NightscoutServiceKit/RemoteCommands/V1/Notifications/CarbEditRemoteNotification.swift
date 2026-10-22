//
//  CarbEditRemoteNotification.swift
//  NightscoutServiceKit
//
//  A caregiver app (LoopFollow) changing or deleting a carb entry Loop already has:
//
//  { "carbs-edit": { "sync-identifier": "…", "carbs": 40, "absorption-time": 3.5,
//                    "food-type": "🍕 Pizza", "start-time": "2026-10-22T12:30:00.000Z" },
//    "otp": "123456", "remote-address": "LoopFollow", "sent-at": "…", "expiration": "…" }
//
//  { "carbs-edit": { "sync-identifier": "…", "delete": true }, … }
//

import Foundation
import LoopKit

public struct CarbEditRemoteNotification: RemoteNotification, Codable {

    public let carbsEdit: CarbEditAction
    public let remoteAddress: String
    public let expiration: Date?
    public let sentAt: Date?
    public let otp: String?
    public let enteredBy: String?
    public let encryptedReturnNotification: String?

    enum CodingKeys: String, CodingKey {
        case carbsEdit = "carbs-edit"
        case remoteAddress = "remote-address"
        case expiration = "expiration"
        case sentAt = "sent-at"
        case otp = "otp"
        case enteredBy = "entered-by"
        case encryptedReturnNotification = "encrypted_return_notification"
    }

    func toRemoteAction() -> Action {
        return .carbsEdit(carbsEdit)
    }

    /// Like a new carb entry: changed carbs change what Loop doses.
    func otpValidationRequired() -> Bool {
        return true
    }

    public static func includedInNotification(_ notification: [String: Any]) -> Bool {
        return notification["carbs-edit"] != nil
    }
}
